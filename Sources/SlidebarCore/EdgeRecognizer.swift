import Foundation

/// One finger on the trackpad. Coordinates are normalized:
/// x goes 0 (left) → 1 (right), y goes 0 (bottom) → 1 (top).
public struct TouchPoint: Equatable {
    public var id: Int32
    public var x: Float
    public var y: Float
    /// Contact size as reported by the trackpad. Palms are much larger than fingertips.
    public var size: Float
    /// Length of the contact ellipse. A palm resting on an edge is long even when only part of it
    /// is on the trackpad (and so its size looks small).
    public var major: Float

    public init(id: Int32, x: Float, y: Float, size: Float = 0, major: Float = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.size = size
        self.major = major
    }
}

/// The four edges of the trackpad.
public enum EdgeSide: String, CaseIterable, Codable, Hashable {
    case left, right, top, bottom

    /// Left and right edges are slid up and down; top and bottom edges left and right.
    public var isVertical: Bool { self == .left || self == .right }
}

/// A third of an edge, for edges split into three double-tap parts. `low` is the bottom of a side
/// edge or the left of the top and bottom edges; `high` the top or the right.
public enum EdgeSection: String, CaseIterable, Codable, Hashable {
    case low, middle, high

    /// Which third a position along the edge (0…1) falls in.
    public static func at(_ position: Float) -> EdgeSection {
        position < 1 / 3 ? .low : position < 2 / 3 ? .middle : .high
    }
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
    /// Continuous: one step per bit of travel (volume, brightness, tabs…).
    case slider
    /// One action per swipe along the edge (next song, next window…).
    case swipe
}

/// The part of the trackpad a gesture belongs to.
public enum EdgeZone: Equatable {
    case edge(EdgeSide)
    case corner(Corner)
}

/// What the recognizer asks the app to do.
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
    /// A slide turned out to be a palm (it grew, or another finger landed soon after):
    /// undo what it changed.
    case slideCancelled(EdgeSide)
    /// Two quick taps in the same place on an edge. `section` says which third, for split edges.
    case doubleTap(EdgeSide, section: EdgeSection?)
    /// Two quick taps in a corner.
    case cornerDoubleTap(Corner)
    /// A finger has rested still on an edge or corner long enough to count as a long press.
    case holdBegan(EdgeZone)
    /// The finger of a long press lifted.
    case holdEnded(EdgeZone)
}

/// The user's settings, as far as recognizing gestures goes.
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
    public var palmLength: Float = 16
    public var edges: [EdgeSide: EdgeKind] = [.left: .slider, .right: .slider, .top: .off, .bottom: .swipe]
    /// Corners that respond to a double-tap.
    public var corners: Set<Corner> = [.topRight]
    /// Edges that respond to a double-tap, on top of whatever sliding or swiping they do.
    public var edgeTaps: Set<EdgeSide> = []
    /// Edges whose double-taps are told apart by third (bottom, middle, top or left, middle, right).
    public var splitEdges: Set<EdgeSide> = []
    /// Edges and corners that respond to a long press.
    public var holdEdges: Set<EdgeSide> = []
    public var holdCorners: Set<Corner> = []

    public init() {}

    public func kind(_ side: EdgeSide) -> EdgeKind { edges[side] ?? .off }

    /// An edge listens when it slides, swipes or has a double-tap.
    public func listens(_ side: EdgeSide) -> Bool { kind(side) != .off || edgeTaps.contains(side) || holdEdges.contains(side) }
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
    // Palms: they rest, then creep; and a finger usually lands next to them soon after.
    public static let engageWindow: Double = 0.5       // a slide has to get going this soon after touching
    public static let palmWatch: Double = 1.5          // another finger this soon means the first was a palm
    public static let holdDuration: Double = 0.5       // a finger resting this long, without moving, is a long press
    public static let lateStartWindow: Double = 0.3    // a finger that landed beside a stray touch may still start this soon
    public static let deliberateTravel: Float = 0.15   // a slide this long is a finger at work, not a creeping palm

    /// The single finger being followed, from touch-down to lift-off.
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
        /// A long press is under way: the finger is held until it lifts.
        var holding = false
    }

    public var config: EdgeConfig
    var gesture: Gesture?
    /// Fingers in the previous frame, so only a fresh touch can start a gesture.
    var previousIDs: Set<Int32> = []
    /// The last single tap (time and place), waiting for a second one.
    var lastTap: (zone: EdgeZone, time: Double, x: Float, y: Float)?
    /// Timestamp of the frame being processed.
    var lastTime: Double = 0
    /// Where and when each finger touched down. `spent` once it has had its chance to start a gesture.
    struct Landing { var time: Double; var x: Float; var y: Float; var spent = false }
    var landings: [Int32: Landing] = [:]

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
        landings = landings.filter { ids.contains($0.key) }
        for t in touches where landings[t.id] == nil {
            landings[t.id] = Landing(time: time, x: t.x, y: t.y)
        }

        if var g = gesture {
            guard let t = touches.first(where: { $0.id == g.id }) else {
                // The finger lifted.
                if g.holding {
                    actions.append(.holdEnded(g.zone))
                    gesture = nil
                    actions.append(.releaseCursor)
                    return actions
                }
                finish(g, time: time, actions: &actions)
                gesture = nil
                actions.append(.releaseCursor)
                return actions
            }
            // Once a long press is under way it lasts until that finger lifts, whatever else happens
            // (you may click or type while dictating).
            if g.holding { return actions }
            // A second finger, a palm, or a press of the button before the gesture started: let it go.
            if !g.engaged && (touches.count > 1 || isPalm(t) || context.buttonHeld) {
                gesture = nil
                actions.append(.releaseCursor)
                return actions
            }
            // A slide that turns out to be a palm: stop it and put things back. A palm creeps, so a
            // finger that lands soon after one counts against it, but not against a slide that has
            // clearly gone somewhere (a thumb brushing the trackpad mid-slide).
            if g.engaged, case .edge(let side) = g.zone, config.kind(side) == .slider {
                let palm = isPalm(t)
                let companion = touches.count > 1 && time - g.startTime <= Self.palmWatch
                    && g.maxTravel < Self.deliberateTravel
                if palm || companion {
                    gesture = nil
                    actions.append(.slideCancelled(side))
                    actions.append(.releaseCursor)
                    return actions
                }
            }
            if update(&g, t, context: context, actions: &actions) {
                gesture = g
            } else {
                gesture = nil
                actions.append(.releaseCursor)
            }
            return actions
        }

        // Only a single finger, fresh on the trackpad, starts a gesture, so sliding in from the middle
        // never triggers. A finger that landed while a stray touch (a thumb brushing the trackpad) was
        // down gets one chance once it's alone, if that's soon; it counts from where it landed.
        guard touches.count == 1, let t = touches.first, let landing = landings[t.id] else { return actions }
        landings[t.id]?.spent = true
        let late = !previousIDs.isEmpty
        if late, landing.spent || time - landing.time > Self.lateStartWindow { return actions }
        let origin = TouchPoint(id: t.id, x: landing.x, y: landing.y, size: t.size, major: t.major)
        guard context.gestureAllowed,
              !context.buttonHeld,
              !isPalm(t),
              let zone = classify(origin)
        else { return actions }

        let start: Float
        if case .edge(let side) = zone { start = side.isVertical ? origin.y : origin.x } else { start = 0 }
        gesture = Gesture(id: t.id, zone: zone, startX: origin.x, startY: origin.y, startTime: landing.time, last: start)
        // Edges that only listen for a double-tap leave the pointer alone.
        if config.freezeCursor, case .edge(let side) = zone, config.kind(side) != .off {
            actions.append(.freezeCursor)
        }
        return actions
    }

    // MARK: - Zones

    func isPalm(_ t: TouchPoint) -> Bool {
        config.palmRejection && (t.size > config.palmSize || t.major > config.palmLength)
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
        if let c = corner(at: t), config.corners.contains(c) || config.holdCorners.contains(c) {
            return .corner(c)
        }
        for side in [EdgeSide.left, .right, .bottom, .top] where config.listens(side) && inEdge(side, t) {
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

        // A finger that rests still long enough on a spot with a long press starts one.
        if !g.engaged, g.maxTravel <= Self.tapMaxTravel, timeSinceStart(g) >= Self.holdDuration, holds(g.zone) {
            g.holding = true
            actions.append(.holdBegan(g.zone))
            return true
        }

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
            // A double-tap or long-press edge: keep following a finger that stays put, drop one that moves.
            return (config.edgeTaps.contains(side) || config.holdEdges.contains(side)) && g.maxTravel <= Self.tapMaxTravel

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
                guard abs(along) >= Self.engageDistance else {
                    // Resting, then creeping: a palm or a finger parked on the edge. On an edge with a
                    // long press, a finger that stays still is waiting for it instead.
                    if config.holdEdges.contains(side) && g.maxTravel <= Self.tapMaxTravel { return true }
                    return timeSinceStart(g) <= Self.engageWindow
                }
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

    func timeSinceStart(_ g: Gesture) -> Double { lastTime - g.startTime }

    func holds(_ zone: EdgeZone) -> Bool {
        switch zone {
        case .edge(let side): return config.holdEdges.contains(side)
        case .corner(let corner): return config.holdCorners.contains(corner)
        }
    }

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
            case .edge(let side):
                guard config.edgeTaps.contains(side) else { break }
                let section = config.splitEdges.contains(side)
                    ? EdgeSection.at(side.isVertical ? g.startY : g.startX) : nil
                actions.append(.doubleTap(side, section: section))
            case .corner(let corner): actions.append(.cornerDoubleTap(corner))
            }
        } else {
            lastTap = (g.zone, time, g.startX, g.startY)
        }
    }
}
