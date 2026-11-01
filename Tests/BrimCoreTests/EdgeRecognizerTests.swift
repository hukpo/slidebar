import XCTest
@testable import BrimCore

final class EdgeRecognizerTests: XCTestCase {

    /// Drives a single finger along a path, one frame every 10 ms, then lifts it.
    private func run(_ r: inout EdgeRecognizer, path: [(Float, Float)], start: Double = 0,
                     context: EdgeContext = EdgeContext(), size: Float = 0.8) -> [EdgeAction] {
        var actions: [EdgeAction] = []
        var time = start
        for (x, y) in path {
            actions += r.process([TouchPoint(id: 1, x: x, y: y, size: size)], time: time, context: context)
            time += 0.01
        }
        actions += r.process([], time: time, context: context)
        return actions
    }

    private func line(from a: (Float, Float), to b: (Float, Float), frames: Int = 30) -> [(Float, Float)] {
        (0...frames).map { i in
            let t = Float(i) / Float(frames)
            return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
        }
    }

    private func steps(_ actions: [EdgeAction]) -> [EdgeAction] {
        actions.filter { if case .step = $0 { return true } else { return false } }
    }

    // MARK: Side sliders

    func testRightEdgeSlideUp() {
        var r = EdgeRecognizer()
        let actions = run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.6)))
        XCTAssertEqual(actions.first, .freezeCursor)
        XCTAssertTrue(actions.contains(.slideBegan(.right)))
        let s = steps(actions)
        // 0.4 travel at 1.5× sensitivity → 0.4 / (0.04 / 1.5) = 15 steps
        XCTAssertEqual(s.count, 15)
        XCTAssertTrue(s.allSatisfy { $0 == .step(.right, up: true, fine: false) })
        XCTAssertEqual(actions.last, .releaseCursor)
    }

    func testLeftEdgeSlideDown() {
        var r = EdgeRecognizer()
        let s = steps(run(&r, path: line(from: (0.02, 0.7), to: (0.02, 0.3))))
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.allSatisfy { $0 == .step(.left, up: false, fine: false) })
    }

    func testMiddleOfTrackpadDoesNothing() {
        var r = EdgeRecognizer()
        XCTAssertEqual(run(&r, path: line(from: (0.5, 0.3), to: (0.5, 0.8))), [])
    }

    func testFingerMovingIntoEdgeDoesNotTrigger() {
        var r = EdgeRecognizer()
        XCTAssertEqual(run(&r, path: line(from: (0.5, 0.5), to: (0.99, 0.5)) + line(from: (0.99, 0.5), to: (0.99, 0.9))), [])
    }

    func testHorizontalMoveFromSideEdgeCancels() {
        var r = EdgeRecognizer()
        let actions = run(&r, path: line(from: (0.02, 0.5), to: (0.4, 0.51)))
        XCTAssertEqual(actions, [.freezeCursor, .releaseCursor])
        XCTAssertFalse(r.isTracking)
    }

    func testBottomQuarterOnly() {
        var config = EdgeConfig()
        config.bottomQuarterOnly = true
        var r = EdgeRecognizer(config: config)
        XCTAssertTrue(steps(run(&r, path: line(from: (0.98, 0.5), to: (0.98, 0.9)))).isEmpty)
        XCTAssertFalse(steps(run(&r, path: line(from: (0.98, 0.1), to: (0.98, 0.5)), start: 5)).isEmpty)
    }

    func testFineControlNeedsKeysAndSetting() {
        var r = EdgeRecognizer()
        let fine = EdgeContext(gestureAllowed: true, fineKeysHeld: true)
        let s = steps(run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.4)), context: fine))
        XCTAssertTrue(s.allSatisfy { $0 == .step(.right, up: true, fine: true) })

        r.config.fineControl = false
        let s2 = steps(run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.4)), start: 5, context: fine))
        XCTAssertTrue(s2.allSatisfy { $0 == .step(.right, up: true, fine: false) })
    }

    func testGestureNotAllowed() {
        var r = EdgeRecognizer()
        let blocked = EdgeContext(gestureAllowed: false)
        XCTAssertEqual(run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.6)), context: blocked), [])
    }

    func testSecondFingerBeforeEngageCancels() {
        var r = EdgeRecognizer()
        _ = r.process([TouchPoint(id: 1, x: 0.98, y: 0.3)], time: 0)
        let actions = r.process([TouchPoint(id: 1, x: 0.98, y: 0.3), TouchPoint(id: 2, x: 0.6, y: 0.3)], time: 0.01)
        XCTAssertEqual(actions, [.releaseCursor])
        XCTAssertFalse(r.isTracking)
    }

    func testHigherSensitivityGivesMoreSteps() {
        var low = EdgeRecognizer()
        low.config.sensitivity = 1
        var high = EdgeRecognizer()
        high.config.sensitivity = 3
        let path = line(from: (0.98, 0.2), to: (0.98, 0.5))
        XCTAssertLessThan(steps(run(&low, path: path)).count, steps(run(&high, path: path)).count)
    }

    func testWiderEdge() {
        var r = EdgeRecognizer()
        XCTAssertTrue(steps(run(&r, path: line(from: (0.9, 0.2), to: (0.9, 0.6)))).isEmpty)
        r.config.edgeWidth = 0.12
        XCTAssertFalse(steps(run(&r, path: line(from: (0.9, 0.2), to: (0.9, 0.6)), start: 5)).isEmpty)
    }

    func testFreezeCursorOff() {
        var r = EdgeRecognizer()
        r.config.freezeCursor = false
        XCTAssertFalse(run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.6))).contains(.freezeCursor))
    }

    // MARK: Configurable edges

    func testEdgeTurnedOffDoesNothing() {
        var r = EdgeRecognizer()
        r.config.edges[.right] = .off
        XCTAssertEqual(run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.6))), [])
    }

    func testTopEdgeSliderUsesHorizontalTravel() {
        var r = EdgeRecognizer()
        r.config.edges[.top] = .slider
        // 0.41 of travel (just past 15 steps, away from a rounding boundary).
        let actions = run(&r, path: line(from: (0.3, 0.96), to: (0.71, 0.96)))
        XCTAssertTrue(actions.contains(.slideBegan(.top)))
        let s = steps(actions)
        XCTAssertEqual(s.count, 15)
        XCTAssertTrue(s.allSatisfy { $0 == .step(.top, up: true, fine: false) })
    }

    func testTopEdgeSlideLeftGoesDown() {
        var r = EdgeRecognizer()
        r.config.edges[.top] = .slider
        let s = steps(run(&r, path: line(from: (0.7, 0.96), to: (0.3, 0.96))))
        XCTAssertTrue(!s.isEmpty && s.allSatisfy { $0 == .step(.top, up: false, fine: false) })
    }

    func testBottomSwipeDirections() {
        var r = EdgeRecognizer()
        XCTAssertTrue(run(&r, path: line(from: (0.3, 0.04), to: (0.6, 0.05))).contains(.swipe(.bottom, forward: true)))
        XCTAssertTrue(run(&r, path: line(from: (0.6, 0.04), to: (0.3, 0.05)), start: 5).contains(.swipe(.bottom, forward: false)))
    }

    func testSwipeFiresOnce() {
        var r = EdgeRecognizer()
        let actions = run(&r, path: line(from: (0.2, 0.04), to: (0.8, 0.04)))
        XCTAssertEqual(actions.filter { $0 == .swipe(.bottom, forward: true) }.count, 1)
    }

    func testSideEdgeAsSwipeUsesVerticalTravel() {
        var r = EdgeRecognizer()
        r.config.edges[.left] = .swipe
        let actions = run(&r, path: line(from: (0.02, 0.3), to: (0.02, 0.6)))
        XCTAssertTrue(actions.contains(.swipe(.left, forward: true)))
        XCTAssertTrue(steps(actions).isEmpty)
    }

    func testBottomEdgeOffDoesNothing() {
        var r = EdgeRecognizer()
        r.config.edges[.bottom] = .off
        XCTAssertEqual(run(&r, path: line(from: (0.3, 0.04), to: (0.6, 0.05))), [])
    }

    func testTapOnEdgeIsReported() {
        var r = EdgeRecognizer()
        XCTAssertTrue(run(&r, path: [(0.5, 0.04), (0.5, 0.04)]).contains(.tap(.bottom)))
    }

    // MARK: Corners

    func testDoubleTapTopRightCorner() {
        var r = EdgeRecognizer()
        // The first tap does nothing visible (corners never freeze the pointer).
        XCTAssertEqual(run(&r, path: [(0.95, 0.95), (0.95, 0.95)], start: 0), [.releaseCursor])
        XCTAssertTrue(run(&r, path: [(0.95, 0.95), (0.95, 0.95)], start: 0.2).contains(.cornerDoubleTap(.topRight)))
    }

    func testSlowSecondTapDoesNothing() {
        var r = EdgeRecognizer()
        _ = run(&r, path: [(0.95, 0.95), (0.95, 0.95)], start: 0)
        XCTAssertFalse(run(&r, path: [(0.95, 0.95), (0.95, 0.95)], start: 2).contains(.cornerDoubleTap(.topRight)))
    }

    func testEveryCornerCanBeEnabled() {
        var r = EdgeRecognizer()
        r.config.corners = Set(Corner.allCases)
        let points: [(Corner, Float, Float)] = [(.topLeft, 0.05, 0.95), (.topRight, 0.95, 0.95),
                                                (.bottomLeft, 0.05, 0.05), (.bottomRight, 0.95, 0.05)]
        var t = 0.0
        for (corner, x, y) in points {
            _ = run(&r, path: [(x, y), (x, y)], start: t)
            XCTAssertTrue(run(&r, path: [(x, y), (x, y)], start: t + 0.2).contains(.cornerDoubleTap(corner)), "\(corner)")
            t += 5
        }
    }

    func testDisabledCornerFallsThroughToEdge() {
        var r = EdgeRecognizer()
        r.config.corners = []
        // A tap in the top-right corner is now just a tap on the right edge.
        XCTAssertTrue(run(&r, path: [(0.98, 0.95), (0.98, 0.95)]).contains(.tap(.right)))
    }

    func testTapsInDifferentCornersDontCombine() {
        var r = EdgeRecognizer()
        r.config.corners = [.topLeft, .topRight]
        _ = run(&r, path: [(0.05, 0.95), (0.05, 0.95)], start: 0)
        XCTAssertFalse(run(&r, path: [(0.95, 0.95), (0.95, 0.95)], start: 0.2).contains(.cornerDoubleTap(.topRight)))
    }

    func testCornerStartedSlideBecomesEdgeSlide() {
        var r = EdgeRecognizer()
        let actions = run(&r, path: line(from: (0.98, 0.95), to: (0.98, 0.5)))
        XCTAssertTrue(actions.contains(.slideBegan(.right)))
        XCTAssertTrue(steps(actions).allSatisfy { $0 == .step(.right, up: false, fine: false) })
    }

    func testCornerStartedHorizontalSlideBecomesTopSlide() {
        var r = EdgeRecognizer()
        r.config.edges[.top] = .slider
        let actions = run(&r, path: line(from: (0.95, 0.97), to: (0.5, 0.97)))
        XCTAssertTrue(actions.contains(.slideBegan(.top)))
    }

    // MARK: Palms

    func testPalmIsIgnored() {
        var r = EdgeRecognizer()
        XCTAssertEqual(run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.6)), size: 4), [])
    }

    func testContactGrowingIntoPalmCancels() {
        var r = EdgeRecognizer()
        _ = r.process([TouchPoint(id: 1, x: 0.98, y: 0.3, size: 0.8)], time: 0)
        XCTAssertTrue(r.isTracking)
        XCTAssertEqual(r.process([TouchPoint(id: 1, x: 0.98, y: 0.3, size: 3.5)], time: 0.01), [.releaseCursor])
        XCTAssertFalse(r.isTracking)
    }

    func testPalmRejectionCanBeTurnedOff() {
        var r = EdgeRecognizer()
        r.config.palmRejection = false
        XCTAssertTrue(run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.6)), size: 4).contains(.slideBegan(.right)))
    }
}
