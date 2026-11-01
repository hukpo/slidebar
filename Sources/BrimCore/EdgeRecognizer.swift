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

/// The four edges of the trackpad.
public enum EdgeSide: String, CaseIterable, Codable, Hashable {
    case left, right, top, bottom

    /// Left and right edges are slid up and down; top and bottom edges left and right.
    public var isVertical: Bool { self == .left || self == .right }
}

/// The four corners of the trackpad.
public enum Corner: String, CaseIterable, Codable, Hashable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isRight: Bool { self == .topRight || self == .bottomRight }
    var isTop: Bool { self == .topLeft || self == .topRight }
    /// The edges that meet at this corner.
    var verticalEdge: EdgeSide { isRight ? .right : .left }
    var horizontalEdge: EdgeSide { isTop ? .top : .bottom }
}

/// How an edge responds.
public enum EdgeKind: Equatable {
    /// Ignored.
    case off
    /// Continuous: one step per bit of travel (volume, brightness, scrolling…).
    case slider
    /// One action per swipe along the edge (next song, next desktop…).
    case swipe
}

public enum EdgeZone: Equatable {
    case edge(EdgeSide)
    case corner(Corner)
}

public enum EdgeAction: Equatable {
    /// Stop the pointer from moving while the finger slides.
    case freezeCursor
    /// Let the pointer move again (safe to send when not frozen).
    case releaseCursor
    /// A slide along an edge was recognized.
    case slideBegan(EdgeSide)
    /// One step along a slider edge. `up` means toward the top (left/right edges)
    /// or toward the right (top/bottom edges). `fine` means a quarter step (⇧⌥).
    case step(EdgeSide, up: Bool, fine: Bool)
    /// A swipe along a swipe edge. `forward` means up (left/right edges) or right (top/bottom edges).
    case swipe(EdgeSide, forward: Bool)
    /// Two quick taps in the same place on an edge.
    case doubleTap(EdgeSide)
    /// Two quick taps in a corner.
    case cornerDoubleTap(Corner)
}

public struct EdgeConfig: Equatable {
    public var edgeWidth: Float = 0.05
    public var sensitivity: Float = 1.5
    /// Only the lower part of the left and right edges responds.
    public var bottomQuarterOnly = false
    public var freezeCursor = true
    public var fineControl = true
    /// Ignore contacts bigger than `palmSize` (a resting palm or thumb base).
    public var palmRejection = true
    public var palmSize: Float = 2.4
    public var edges: [EdgeSide: EdgeKind] = [.left: .slider, .right: .slider, .top: .off, .bottom: .swipe]
    /// Corners that respond to a double-tap.
    public var corners: Set<Corner> = [.topRight]

    public init() {}

    public func kind(_ side: EdgeSide) -> EdgeKind { edges[side] ?? .off }
}

/// Per-frame input that isn't about touches.
public struct EdgeContext: Equatable {
    /// False while paused or while a required modifier key isn't held.
    public var gestureAllowed: Bool
    /// True while ⇧⌥ are held.
    public var fineKeysHeld: Bool
    /// True while the trackpad (or mouse) button is pressed: the user is clicking or dragging.
    public var buttonHeld: Bool

    public init(gestureAllowed: Bool = true, fineKeysHeld: Bool = false, buttonHeld: Bool = false) {
        self.gestureAllowed = gestureAllowed
        self.fineKeysHeld = fineKeysHeld
        self.buttonHeld = buttonHeld
    }
}

/// Turns raw trackpad frames into edge actions. Pure logic, no system calls.
public struct EdgeRecognizer {
    // Tuning, in normalized trackpad units.
    // Accident-proofing: a gesture has to be deliberate before it does anything.
    public static let baseStepDistance: Float = 0.04   // finger travel per step at 1× sensitivity
    public static let engageDistance: Float = 0.025    // travel along the edge before a slide starts
    public static let straightness: Float = 0.6        // before starting, sideways travel must stay under this × along
    public static let laneDrift: Float = 0.10          // a started slide stops if the finger wanders this far across
    public static let stripHeight: Float = 0.09        // depth of the top and bottom edges
    public static let bottomQuarter: Float = 0.25
    public static let cornerSize: Float = 0.10
    public static let swipeDistance: Float = 0.15
    public static let swipeStraightness: Float = 0.4
    public static let swipeMaxDuration: Double = 0.4   // swipes are quick; slow pointer moves along an edge aren't
    public static let tapMaxTravel: Float = 0.03
    public static let tapMaxDuration: Double = 0.25
    public static let doubleTapWindow: Double = 0.4
    public static let doubleTapSpread: Float = 0.05    // both taps land in about the same place

    struct Gesture {
        var id: Int32
        var zone: EdgeZone
        var startX: Float
        var startY: Float
        var startTime: Double
        var last: Float
        var maxTravel: Float = 0
        var engaged = false
        var accumulated: Float = 0
    }

    public var config: EdgeConfig
    var gesture: Gesture?
    var previousIDs: Set<Int32> = []
    /// The last single tap (time and place), waiting for a second one.
    var lastTap: (zone: EdgeZone, time: Double, x: Float, y: Float)?

    public init(config: EdgeConfig = EdgeConfig()) {
        self.config = config
    }

    public var isTracking: Bool { gesture != nil }

    /// Feed one trackpad frame (only fingers that are touching). Returns the actions to perform.
    public mutating func process(_ touches: [TouchPoint], time: Double, context: EdgeContext = EdgeContext()) -> [EdgeAction] {
        lastTime = time
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
            // A second finger, a palm, or a press of the button before the gesture started: let it go.
            if !g.engaged && (touches.count > 1 || isPalm(t) || context.buttonHeld) {
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
              !context.buttonHeld,
              touches.count == 1,
              previousIDs.isEmpty,
              let t = touches.first,
              !isPalm(t),
              let zone = classify(t)
        else { return actions }

        let start: Float
        if case .edge(let side) = zone { start = side.isVertical ? t.y : t.x } else { start = 0 }
        gesture = Gesture(id: t.id, zone: zone, startX: t.x, startY: t.y, startTime: time, last: start)
        if config.freezeCursor, case .edge = zone {
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

    func corner(at t: TouchPoint) -> Corner? {
        let c = Self.cornerSize
        let right = t.x >= 1 - c, left = t.x <= c, top = t.y >= 1 - c, bottom = t.y <= c
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        default: return nil
        }
    }

    func inEdge(_ side: EdgeSide, _ t: TouchPoint) -> Bool {
        switch side {
        case .left: return t.x <= config.edgeWidth && sideAllowed(atY: t.y)
        case .right: return t.x >= 1 - config.edgeWidth && sideAllowed(atY: t.y)
        case .top: return t.y >= 1 - Self.stripHeight
        case .bottom: return t.y <= Self.stripHeight
        }
    }

    func classify(_ t: TouchPoint) -> EdgeZone? {
        if let c = corner(at: t), config.corners.contains(c) {
            return .corner(c)
        }
        for side in [EdgeSide.left, .right, .bottom, .top] where config.kind(side) != .off && inEdge(side, t) {
            return .edge(side)
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
        case .edge(let side):
            return updateEdge(side, &g, t, dx: dx, dy: dy, context: context, actions: &actions)

        case .corner(let corner):
            guard g.maxTravel > Self.tapMaxTravel else { return true }
            // A slide that starts in a corner but runs along one of its edges belongs to that edge.
            let start = TouchPoint(id: t.id, x: g.startX, y: g.startY)
            let side = abs(dy) > abs(dx) ? corner.verticalEdge : corner.horizontalEdge
            guard config.kind(side) != .off, inEdge(side, start) else { return false }
            g.zone = .edge(side)
            g.last = side.isVertical ? g.startY : g.startX
            if config.freezeCursor { actions.append(.freezeCursor) }
            return updateEdge(side, &g, t, dx: dx, dy: dy, context: context, actions: &actions)
        }
    }

    mutating func updateEdge(_ side: EdgeSide, _ g: inout Gesture, _ t: TouchPoint, dx: Float, dy: Float,
                             context: EdgeContext, actions: inout [EdgeAction]) -> Bool {
        let along = side.isVertical ? dy : dx
        let across = side.isVertical ? dx : dy
        let position = side.isVertical ? t.y : t.x
        // How far the finger may stray from the edge before it clearly isn't an edge gesture.
        let zoneDepth = side.isVertical ? config.edgeWidth : Self.stripHeight

        switch config.kind(side) {
        case .off:
            return false

        case .swipe:
            if !g.engaged {
                if abs(across) > zoneDepth * 1.5 { return false }               // left the edge
                if timeSinceStart(g) > Self.swipeMaxDuration { return false }  // too slow: a pointer move
                if abs(along) >= Self.swipeDistance {
                    guard abs(across) <= abs(along) * Self.swipeStraightness else { return false }
                    g.engaged = true
                    actions.append(.swipe(side, forward: along > 0))
                }
            }
            return true

        case .slider:
            if !g.engaged {
                if abs(across) > zoneDepth * 1.5 { return false }  // left the edge before starting
                guard abs(along) >= Self.engageDistance else { return true }
                guard abs(across) <= abs(along) * Self.straightness else { return false } // diagonal: a pointer move
                g.engaged = true
                actions.append(.slideBegan(side))
                // g.last still holds the start, so the travel so far counts.
            }

            // Once sliding, wandering far off the edge ends the slide.
            if abs(across) > Self.laneDrift { return false }

            let stepDistance = Self.baseStepDistance / max(config.sensitivity, 0.1)
            g.accumulated += position - g.last
            g.last = position

            let fine = config.fineControl && context.fineKeysHeld
            while g.accumulated >= stepDistance {
                g.accumulated -= stepDistance
                actions.append(.step(side, up: true, fine: fine))
            }
            while g.accumulated <= -stepDistance {
                g.accumulated += stepDistance
                actions.append(.step(side, up: false, fine: fine))
            }
            return true
        }
    }

    var lastTime: Double = 0

    func timeSinceStart(_ g: Gesture) -> Double { lastTime - g.startTime }

    mutating func finish(_ g: Gesture, time: Double, actions: inout [EdgeAction]) {
        let isTap = !g.engaged
            && g.maxTravel <= Self.tapMaxTravel
            && time - g.startTime <= Self.tapMaxDuration
        guard isTap else { lastTap = nil; return }

        // Only a second tap, soon after and in the same place, counts.
        if let last = lastTap, last.zone == g.zone, g.startTime - last.time <= Self.doubleTapWindow,
           abs(g.startX - last.x) <= Self.doubleTapSpread, abs(g.startY - last.y) <= Self.doubleTapSpread {
            lastTap = nil
            switch g.zone {
            case .edge(let side): actions.append(.doubleTap(side))
            case .corner(let corner): actions.append(.cornerDoubleTap(corner))
            }
        } else {
            lastTap = (g.zone, time, g.startX, g.startY)
        }
    }
}
