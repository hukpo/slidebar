import Foundation

/// One finger on the trackpad. Coordinates are normalized:
/// x goes 0 (left) → 1 (right), y goes 0 (bottom) → 1 (top).
public struct TouchPoint: Equatable {
    public var id: Int32
    public var x: Float
    public var y: Float
    /// Contact size as reported by the trackpad. Palms are much larger than fingertips.
    public var size: Float

    public init(id: Int32, x: Float, y: Float, size: Float = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.size = size
    }
}

public enum EdgeZone: Equatable {
    case left, right, bottom, corner
}

public enum EdgeControl: Equatable {
    case brightness, volume
}

public enum EdgeAction: Equatable {
    /// Stop the pointer from moving while the finger slides.
    case freezeCursor
    /// Let the pointer move again (safe to send when not frozen).
    case releaseCursor
    /// A slide along a side edge was recognized.
    case slideBegan(EdgeControl)
    /// Move a control one step. `fine` means a quarter step (⇧⌥).
    case step(EdgeControl, up: Bool, fine: Bool)
    case toggleMute
    case playPause
    case nextTrack
    case previousTrack
}

public struct EdgeConfig: Equatable {
    public var edgeWidth: Float = 0.05
    public var sensitivity: Float = 1.5
    public var swapSides = false
    public var bottomQuarterOnly = false
    public var quickMute = true
    public var mediaStrip = true
    public var tapToPlay = false
    public var freezeCursor = true
    public var fineControl = true
    /// Ignore contacts bigger than `palmSize` (a resting palm or thumb base).
    public var palmRejection = true
    public var palmSize: Float = 2.4

    public init() {}
}

/// Per-frame input that isn't about touches.
public struct EdgeContext: Equatable {
    /// False while paused or while a required modifier key isn't held.
    public var gestureAllowed: Bool
    /// True while ⇧⌥ are held.
    public var fineKeysHeld: Bool

    public init(gestureAllowed: Bool = true, fineKeysHeld: Bool = false) {
        self.gestureAllowed = gestureAllowed
        self.fineKeysHeld = fineKeysHeld
    }
}

/// Turns raw trackpad frames into edge actions. Pure logic, no system calls.
public struct EdgeRecognizer {
    // Tuning, in normalized trackpad units.
    public static let baseStepDistance: Float = 0.04   // finger travel per step at 1× sensitivity
    public static let engageDistance: Float = 0.012    // vertical travel before a slide starts
    public static let cancelDistance: Float = 0.06     // sideways travel that cancels a slide
    public static let bottomStripHeight: Float = 0.09
    public static let bottomQuarter: Float = 0.25
    public static let cornerSize: Float = 0.14
    public static let swipeDistance: Float = 0.12
    public static let tapMaxTravel: Float = 0.03
    public static let tapMaxDuration: Double = 0.3
    public static let doubleTapWindow: Double = 0.45

    struct Gesture {
        var id: Int32
        var zone: EdgeZone
        var startX: Float
        var startY: Float
        var startTime: Double
        var lastY: Float
        var maxTravel: Float = 0
        var engaged = false
        var accumulated: Float = 0
    }

    public var config: EdgeConfig
    var gesture: Gesture?
    var previousIDs: Set<Int32> = []
    var lastCornerTap: Double?

    public init(config: EdgeConfig = EdgeConfig()) {
        self.config = config
    }

    public var isTracking: Bool { gesture != nil }

    public func control(for zone: EdgeZone) -> EdgeControl? {
        switch zone {
        case .left: return config.swapSides ? .volume : .brightness
        case .right: return config.swapSides ? .brightness : .volume
        case .bottom, .corner: return nil
        }
    }

    /// Feed one trackpad frame (only fingers that are touching). Returns the actions to perform.
    public mutating func process(_ touches: [TouchPoint], time: Double, context: EdgeContext = EdgeContext()) -> [EdgeAction] {
        let ids = Set(touches.map(\.id))
        defer { previousIDs = ids }
        var actions: [EdgeAction] = []

        if var g = gesture {
            guard let t = touches.first(where: { $0.id == g.id }) else {
                // The finger lifted.
                finish(g, time: time, actions: &actions)
                gesture = nil
                actions.append(.releaseCursor)
                return actions
            }
            // A second finger, or the contact grows into a palm, before the slide started: let it go.
            if !g.engaged && (touches.count > 1 || isPalm(t)) {
                gesture = nil
                actions.append(.releaseCursor)
                return actions
            }
            if update(&g, t, context: context, actions: &actions) {
                gesture = g
            } else {
                gesture = nil
                actions.append(.releaseCursor)
            }
            return actions
        }

        // Only start on a single fresh finger, so sliding in from the middle never triggers.
        guard context.gestureAllowed,
              touches.count == 1,
              previousIDs.isEmpty,
              let t = touches.first,
              !isPalm(t),
              let zone = classify(t)
        else { return actions }

        gesture = Gesture(id: t.id, zone: zone, startX: t.x, startY: t.y, startTime: time, lastY: t.y)
        if config.freezeCursor && zone != .corner {
            actions.append(.freezeCursor)
        }
        return actions
    }

    // MARK: - Zones

    func isPalm(_ t: TouchPoint) -> Bool {
        config.palmRejection && t.size > config.palmSize
    }

    func sideAllowed(atY y: Float) -> Bool {
        !config.bottomQuarterOnly || y <= Self.bottomQuarter
    }

    func classify(_ t: TouchPoint) -> EdgeZone? {
        let w = config.edgeWidth
        if config.quickMute && t.x >= 1 - Self.cornerSize && t.y >= 1 - Self.cornerSize {
            return .corner
        }
        if sideAllowed(atY: t.y) {
            if t.x <= w { return .left }
            if t.x >= 1 - w { return .right }
        }
        if config.mediaStrip && t.y <= Self.bottomStripHeight {
            return .bottom
        }
        return nil
    }

    // MARK: - Updates

    /// Returns false when the gesture should be dropped.
    mutating func update(_ g: inout Gesture, _ t: TouchPoint, context: EdgeContext, actions: inout [EdgeAction]) -> Bool {
        let dx = t.x - g.startX
        let dy = t.y - g.startY
        g.maxTravel = max(g.maxTravel, (dx * dx + dy * dy).squareRoot())

        switch g.zone {
        case .left, .right:
            return updateSlide(&g, t, dx: dx, dy: dy, context: context, actions: &actions)

        case .bottom:
            if !g.engaged {
                if abs(dx) >= Self.swipeDistance && abs(dx) > abs(dy) * 1.5 {
                    g.engaged = true
                    actions.append(dx > 0 ? .nextTrack : .previousTrack)
                } else if dy > Self.swipeDistance {
                    return false // moved up into the trackpad, not a strip gesture
                }
            }
            return true

        case .corner:
            if g.maxTravel > Self.tapMaxTravel {
                // A slide that started in the corner but runs down the right edge.
                if g.startX >= 1 - config.edgeWidth, abs(dy) > abs(dx), sideAllowed(atY: g.startY) {
                    g.zone = .right
                    if config.freezeCursor { actions.append(.freezeCursor) }
                    return updateSlide(&g, t, dx: dx, dy: dy, context: context, actions: &actions)
                }
                return false
            }
            return true
        }
    }

    mutating func updateSlide(_ g: inout Gesture, _ t: TouchPoint, dx: Float, dy: Float, context: EdgeContext, actions: inout [EdgeAction]) -> Bool {
        guard let control = control(for: g.zone) else { return false }

        if !g.engaged {
            if abs(dx) >= Self.cancelDistance && abs(dx) > abs(dy) {
                return false // moving across the trackpad, not along the edge
            }
            guard abs(dy) >= Self.engageDistance else { return true }
            g.engaged = true
            actions.append(.slideBegan(control))
            // g.lastY still holds the start, so the travel so far counts.
        }

        let sensitivity = max(config.sensitivity, 0.1)
        let stepDistance = Self.baseStepDistance / sensitivity
        g.accumulated += t.y - g.lastY
        g.lastY = t.y

        let fine = config.fineControl && context.fineKeysHeld
        while g.accumulated >= stepDistance {
            g.accumulated -= stepDistance
            actions.append(.step(control, up: true, fine: fine))
        }
        while g.accumulated <= -stepDistance {
            g.accumulated += stepDistance
            actions.append(.step(control, up: false, fine: fine))
        }
        return true
    }

    mutating func finish(_ g: Gesture, time: Double, actions: inout [EdgeAction]) {
        let isTap = !g.engaged
            && g.maxTravel <= Self.tapMaxTravel
            && time - g.startTime <= Self.tapMaxDuration

        switch g.zone {
        case .bottom:
            if isTap && config.tapToPlay {
                actions.append(.playPause)
            }
        case .corner:
            guard isTap else { return }
            if let last = lastCornerTap, time - last <= Self.doubleTapWindow {
                lastCornerTap = nil
                actions.append(.toggleMute)
            } else {
                lastCornerTap = time
            }
        case .left, .right:
            break
        }
    }
}
