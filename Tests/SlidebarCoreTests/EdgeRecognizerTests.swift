import XCTest
@testable import SlidebarCore

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

    func testDoubleTapOnEdgeIsReported() {
        var r = EdgeRecognizer()
        r.config.edgeTaps = [.bottom]
        XCTAssertFalse(run(&r, path: [(0.5, 0.04), (0.5, 0.04)], start: 0).contains(.doubleTap(.bottom)))
        XCTAssertTrue(run(&r, path: [(0.5, 0.04), (0.5, 0.04)], start: 0.2).contains(.doubleTap(.bottom)))
    }

    func testDoubleTapOnEdgeWithoutTapActionIsQuiet() {
        var r = EdgeRecognizer()
        _ = run(&r, path: [(0.5, 0.04), (0.5, 0.04)], start: 0)
        XCTAssertFalse(run(&r, path: [(0.5, 0.04), (0.5, 0.04)], start: 0.2).contains(.doubleTap(.bottom)))
    }

    func testDoubleTapOnlyEdgeListensForTaps() {
        var r = EdgeRecognizer()
        r.config.edges[.top] = .off
        r.config.edgeTaps = [.top]
        let first = run(&r, path: [(0.5, 0.96), (0.5, 0.96)], start: 0)
        XCTAssertFalse(first.contains(.freezeCursor), "a tap-only edge leaves the pointer alone")
        XCTAssertTrue(run(&r, path: [(0.5, 0.96), (0.5, 0.96)], start: 0.2).contains(.doubleTap(.top)))
    }

    func testDoubleTapOnlyEdgeIgnoresSlides() {
        var r = EdgeRecognizer()
        r.config.edges[.top] = .off
        r.config.edgeTaps = [.top]
        let actions = run(&r, path: line(from: (0.3, 0.96), to: (0.7, 0.96)))
        XCTAssertTrue(steps(actions).isEmpty)
        XCTAssertFalse(actions.contains(.freezeCursor))
        XCTAssertFalse(actions.contains { if case .swipe = $0 { return true } else { return false } })
    }

    func testDoubleTapAlongsideSlider() {
        var r = EdgeRecognizer()
        r.config.edges[.top] = .slider
        r.config.edgeTaps = [.top]
        _ = run(&r, path: [(0.5, 0.96), (0.5, 0.96)], start: 0)
        XCTAssertTrue(run(&r, path: [(0.5, 0.96), (0.5, 0.96)], start: 0.2).contains(.doubleTap(.top)))
        // …and the same edge still slides.
        XCTAssertFalse(steps(run(&r, path: line(from: (0.3, 0.96), to: (0.7, 0.96)), start: 5)).isEmpty)
    }

    // MARK: Accidents

    func testSingleClickOnEdgeDoesNothing() {
        var r = EdgeRecognizer()
        let actions = run(&r, path: [(0.5, 0.04), (0.5, 0.04)])
        XCTAssertFalse(actions.contains { if case .doubleTap = $0 { return true } else { return false } })
    }

    func testDoubleTapInDifferentPlacesDoesNothing() {
        var r = EdgeRecognizer()
        r.config.edgeTaps = [.bottom]
        _ = run(&r, path: [(0.3, 0.04), (0.3, 0.04)], start: 0)
        XCTAssertFalse(run(&r, path: [(0.6, 0.04), (0.6, 0.04)], start: 0.2).contains(.doubleTap(.bottom)))
    }

    func testDiagonalPointerMoveFromEdgeDoesNotSlide() {
        var r = EdgeRecognizer()
        // Starts on the right edge but heads up and into the trackpad, like moving the pointer.
        let actions = run(&r, path: line(from: (0.98, 0.2), to: (0.85, 0.35)))
        XCTAssertFalse(actions.contains(.slideBegan(.right)))
        XCTAssertTrue(steps(actions).isEmpty)
    }

    func testSmallWiggleDoesNotSlide() {
        var r = EdgeRecognizer()
        XCTAssertTrue(steps(run(&r, path: line(from: (0.98, 0.30), to: (0.98, 0.32)))).isEmpty)
    }

    func testWanderingOffTheEdgeEndsTheSlide() {
        var r = EdgeRecognizer()
        // Slides up the edge, then drifts well into the trackpad: steps stop once it leaves the lane.
        let path = line(from: (0.98, 0.2), to: (0.98, 0.4)) + line(from: (0.98, 0.4), to: (0.6, 0.8))
        let s = steps(run(&r, path: path))
        // Staying on the edge for the whole 0.6 of travel would give 22 steps.
        XCTAssertLessThan(s.count, 13)
        XCTAssertFalse(s.isEmpty)
    }

    func testSlowDragAlongBottomDoesNotSwipe() {
        var r = EdgeRecognizer()
        // 0.4 of travel over 1.2 s: a pointer move, not a swipe.
        let actions = run(&r, path: line(from: (0.3, 0.04), to: (0.7, 0.04), frames: 120))
        XCTAssertFalse(actions.contains(.swipe(.bottom, forward: true)))
    }

    func testCurvedSwipeDoesNotCount() {
        var r = EdgeRecognizer()
        // Leaves the bottom edge on the way: not a swipe along it.
        XCTAssertFalse(run(&r, path: line(from: (0.3, 0.04), to: (0.6, 0.25))).contains(.swipe(.bottom, forward: true)))
    }

    func testHoldingTheButtonPreventsGestures() {
        var r = EdgeRecognizer()
        let dragging = EdgeContext(gestureAllowed: true, fineKeysHeld: false, buttonHeld: true)
        XCTAssertEqual(run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.6)), context: dragging), [])
    }

    func testPressingTheButtonMidwayCancelsBeforeStart() {
        var r = EdgeRecognizer()
        _ = r.process([TouchPoint(id: 1, x: 0.98, y: 0.3)], time: 0)
        let actions = r.process([TouchPoint(id: 1, x: 0.98, y: 0.305)], time: 0.01,
                                context: EdgeContext(gestureAllowed: true, fineKeysHeld: false, buttonHeld: true))
        XCTAssertEqual(actions, [.releaseCursor])
        XCTAssertFalse(r.isTracking)
    }

    func testDoubleClickJustOutsideTheCornerDoesNothing() {
        var r = EdgeRecognizer()
        // Corners are the outer 10% of the trackpad, so (0.88, 0.88) is outside them.
        _ = run(&r, path: [(0.88, 0.88), (0.88, 0.88)], start: 0)
        XCTAssertFalse(run(&r, path: [(0.88, 0.88), (0.88, 0.88)], start: 0.2).contains(.cornerDoubleTap(.topRight)))
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
        r.config.edgeTaps = [.right]
        // A double-tap in the top-right corner is then just a double-tap on the right edge.
        _ = run(&r, path: [(0.98, 0.95), (0.98, 0.95)], start: 0)
        XCTAssertTrue(run(&r, path: [(0.98, 0.95), (0.98, 0.95)], start: 0.2).contains(.doubleTap(.right)))
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

    // MARK: Resting palms

    func testLongPalmEdgeIsIgnoredEvenWhenSmall() {
        // Only part of the palm is on the trackpad, so its size looks like a finger, but it's long.
        var r = EdgeRecognizer()
        var actions: [EdgeAction] = []
        var time = 0.0
        for (x, y) in line(from: (0.98, 0.2), to: (0.98, 0.6)) {
            actions += r.process([TouchPoint(id: 1, x: x, y: y, size: 1.2, major: 21)], time: time)
            time += 0.01
        }
        XCTAssertFalse(actions.contains(.slideBegan(.right)))
        XCTAssertTrue(steps(actions).isEmpty)
    }

    func testRestingThenCreepingDoesNotSlide() {
        var r = EdgeRecognizer()
        let rest = Array(repeating: (Float(0.98), Float(0.3)), count: 80) // 0.8 s still
        let actions = run(&r, path: rest + line(from: (0.98, 0.3), to: (0.98, 0.6)))
        XCTAssertFalse(actions.contains(.slideBegan(.right)))
        XCTAssertTrue(steps(actions).isEmpty)
    }

    func testSlowDeliberateSlideStillWorks() {
        var r = EdgeRecognizer()
        let actions = run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.6), frames: 300)) // 3 s
        XCTAssertTrue(actions.contains(.slideBegan(.right)))
        XCTAssertGreaterThan(steps(actions).count, 10)
    }

    func testFingerLandingSoonAfterUndoesTheSlide() {
        var r = EdgeRecognizer()
        var actions: [EdgeAction] = []
        var time = 0.0
        for (x, y) in line(from: (0.98, 0.2), to: (0.98, 0.4), frames: 20) {
            actions += r.process([TouchPoint(id: 1, x: x, y: y, size: 0.8)], time: time)
            time += 0.01
        }
        XCTAssertTrue(actions.contains(.slideBegan(.right)))
        // The index finger lands to move the pointer: the "slide" was a palm.
        let after = r.process([TouchPoint(id: 1, x: 0.98, y: 0.4, size: 0.8),
                               TouchPoint(id: 2, x: 0.5, y: 0.5, size: 0.8)], time: time)
        XCTAssertEqual(after, [.slideCancelled(.right), .releaseCursor])
        XCTAssertFalse(r.isTracking)
    }

    func testContactGrowingIntoPalmMidSlideUndoesIt() {
        var r = EdgeRecognizer()
        var actions: [EdgeAction] = []
        var time = 0.0
        for (x, y) in line(from: (0.98, 0.2), to: (0.98, 0.4), frames: 20) {
            actions += r.process([TouchPoint(id: 1, x: x, y: y, size: 0.8)], time: time)
            time += 0.01
        }
        XCTAssertTrue(actions.contains(.slideBegan(.right)))
        let after = r.process([TouchPoint(id: 1, x: 0.98, y: 0.42, size: 3.2)], time: time)
        XCTAssertEqual(after, [.slideCancelled(.right), .releaseCursor])
    }

    func testSecondFingerLongIntoASlideDoesNotUndoIt() {
        var r = EdgeRecognizer()
        var time = 0.0
        for (x, y) in line(from: (0.98, 0.2), to: (0.98, 0.8), frames: 200) { // 2 s
            _ = r.process([TouchPoint(id: 1, x: x, y: y, size: 0.8)], time: time)
            time += 0.01
        }
        let after = r.process([TouchPoint(id: 1, x: 0.98, y: 0.8, size: 0.8),
                               TouchPoint(id: 2, x: 0.5, y: 0.5, size: 0.8)], time: time)
        XCTAssertFalse(after.contains(.slideCancelled(.right)))
    }
}
