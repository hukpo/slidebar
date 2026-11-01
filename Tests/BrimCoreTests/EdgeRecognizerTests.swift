import XCTest
@testable import BrimCore

final class EdgeRecognizerTests: XCTestCase {

    /// Drives a single finger along a path, one frame every 10 ms, then lifts it.
    private func run(_ r: inout EdgeRecognizer, path: [(Float, Float)], start: Double = 0,
                     context: EdgeContext = EdgeContext(), id: Int32 = 1) -> [EdgeAction] {
        var actions: [EdgeAction] = []
        var time = start
        for (x, y) in path {
            actions += r.process([TouchPoint(id: id, x: x, y: y)], time: time, context: context)
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

    func testRightEdgeSlideUpRaisesVolume() {
        var r = EdgeRecognizer()
        let actions = run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.6)))
        XCTAssertEqual(actions.first, .freezeCursor)
        XCTAssertTrue(actions.contains(.slideBegan(.volume)))
        let s = steps(actions)
        // 0.4 travel at 1.5× sensitivity → 0.4 / (0.04 / 1.5) = 15 steps
        XCTAssertEqual(s.count, 15)
        XCTAssertTrue(s.allSatisfy { $0 == .step(.volume, up: true, fine: false) })
        XCTAssertEqual(actions.last, .releaseCursor)
    }

    func testLeftEdgeSlideDownLowersBrightness() {
        var r = EdgeRecognizer()
        let s = steps(run(&r, path: line(from: (0.02, 0.7), to: (0.02, 0.3))))
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.allSatisfy { $0 == .step(.brightness, up: false, fine: false) })
    }

    func testSwapSides() {
        var config = EdgeConfig()
        config.swapSides = true
        var r = EdgeRecognizer(config: config)
        let s = steps(run(&r, path: line(from: (0.02, 0.2), to: (0.02, 0.5))))
        XCTAssertTrue(s.allSatisfy { $0 == .step(.volume, up: true, fine: false) })
        XCTAssertFalse(s.isEmpty)
    }

    func testMiddleOfTrackpadDoesNothing() {
        var r = EdgeRecognizer()
        XCTAssertEqual(run(&r, path: line(from: (0.5, 0.3), to: (0.5, 0.8))), [])
    }

    func testFingerMovingIntoEdgeDoesNotTrigger() {
        var r = EdgeRecognizer()
        // Starts in the middle and ends at the edge: must stay a normal pointer move.
        XCTAssertEqual(run(&r, path: line(from: (0.5, 0.5), to: (0.99, 0.5)) + line(from: (0.99, 0.5), to: (0.99, 0.9))), [])
    }

    func testHorizontalMoveFromEdgeCancels() {
        var r = EdgeRecognizer()
        let actions = run(&r, path: line(from: (0.02, 0.5), to: (0.4, 0.51)))
        XCTAssertTrue(steps(actions).isEmpty)
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
        XCTAssertTrue(s.allSatisfy { $0 == .step(.volume, up: true, fine: true) })

        r.config.fineControl = false
        let s2 = steps(run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.4)), start: 5, context: fine))
        XCTAssertTrue(s2.allSatisfy { $0 == .step(.volume, up: true, fine: false) })
    }

    func testRequireModifierGate() {
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

    func testDoubleTapCornerMutes() {
        var r = EdgeRecognizer()
        let tap1 = run(&r, path: [(0.95, 0.95), (0.95, 0.95)], start: 0)
        XCTAssertEqual(tap1, [.releaseCursor])
        let tap2 = run(&r, path: [(0.95, 0.95), (0.95, 0.95)], start: 0.2)
        XCTAssertTrue(tap2.contains(.toggleMute))
    }

    func testSlowSecondCornerTapDoesNotMute() {
        var r = EdgeRecognizer()
        _ = run(&r, path: [(0.95, 0.95), (0.95, 0.95)], start: 0)
        XCTAssertFalse(run(&r, path: [(0.95, 0.95), (0.95, 0.95)], start: 2).contains(.toggleMute))
    }

    func testCornerStartedSlideBecomesVolume() {
        var r = EdgeRecognizer()
        let actions = run(&r, path: line(from: (0.98, 0.95), to: (0.98, 0.5)))
        XCTAssertTrue(actions.contains(.slideBegan(.volume)))
        XCTAssertTrue(steps(actions).allSatisfy { $0 == .step(.volume, up: false, fine: false) })
    }

    func testMediaStripSwipes() {
        var r = EdgeRecognizer()
        XCTAssertTrue(run(&r, path: line(from: (0.3, 0.04), to: (0.6, 0.05))).contains(.nextTrack))
        XCTAssertTrue(run(&r, path: line(from: (0.6, 0.04), to: (0.3, 0.05)), start: 5).contains(.previousTrack))
    }

    func testSwipeFiresOnce() {
        var r = EdgeRecognizer()
        let actions = run(&r, path: line(from: (0.2, 0.04), to: (0.8, 0.04)))
        XCTAssertEqual(actions.filter { $0 == .nextTrack }.count, 1)
    }

    func testTapToPlayIsOptIn() {
        var r = EdgeRecognizer()
        XCTAssertFalse(run(&r, path: [(0.5, 0.04), (0.5, 0.04)]).contains(.playPause))
        r.config.tapToPlay = true
        XCTAssertTrue(run(&r, path: [(0.5, 0.04), (0.5, 0.04)], start: 5).contains(.playPause))
    }

    func testMediaStripCanBeDisabled() {
        var config = EdgeConfig()
        config.mediaStrip = false
        var r = EdgeRecognizer(config: config)
        XCTAssertEqual(run(&r, path: line(from: (0.3, 0.04), to: (0.6, 0.05))), [])
    }

    func testFreezeCursorOff() {
        var config = EdgeConfig()
        config.freezeCursor = false
        var r = EdgeRecognizer(config: config)
        XCTAssertFalse(run(&r, path: line(from: (0.98, 0.2), to: (0.98, 0.6))).contains(.freezeCursor))
    }

    func testHigherSensitivityGivesMoreSteps() {
        var low = EdgeRecognizer()
        low.config.sensitivity = 1
        var high = EdgeRecognizer()
        high.config.sensitivity = 3
        let path = line(from: (0.98, 0.2), to: (0.98, 0.5))
        XCTAssertLessThan(steps(run(&low, path: path)).count, steps(run(&high, path: path)).count)
    }

    func testPalmIsIgnored() {
        var r = EdgeRecognizer()
        var actions: [EdgeAction] = []
        for i in 0...30 {
            actions += r.process([TouchPoint(id: 1, x: 0.98, y: 0.2 + Float(i) * 0.015, size: 4)], time: Double(i) * 0.01)
        }
        actions += r.process([], time: 1)
        XCTAssertEqual(actions, [])
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
        var actions: [EdgeAction] = []
        for i in 0...30 {
            actions += r.process([TouchPoint(id: 1, x: 0.98, y: 0.2 + Float(i) * 0.015, size: 4)], time: Double(i) * 0.01)
        }
        XCTAssertTrue(actions.contains(.slideBegan(.volume)))
    }

    func testWiderEdge() {
        var r = EdgeRecognizer()
        XCTAssertTrue(steps(run(&r, path: line(from: (0.9, 0.2), to: (0.9, 0.6)))).isEmpty)
        r.config.edgeWidth = 0.12
        XCTAssertFalse(steps(run(&r, path: line(from: (0.9, 0.2), to: (0.9, 0.6)), start: 5)).isEmpty)
    }
}
