import AppKit
import BrimCore
import CBrimPrivate

/// `Brim --selftest`: checks the system hooks Brim relies on, then restores every level it touched.
enum SelfTest {
    /// `Brim --simulate`: drives the real gesture engine with synthetic finger paths and checks
    /// that volume, brightness and mute actually change. Restores every level afterwards.
    static func runSimulationIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--simulate") else { return false }
        func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
        func line(_ ok: Bool, _ name: String, _ detail: String) { print("\(ok ? "PASS" : "FAIL")  \(name)  (\(detail))") }
        let engine = EdgeEngine.shared
        let prefs = Prefs.shared
        let savedPaused = prefs.paused, savedModifier = prefs.requireModifier
        let savedEdges = prefs.edges, savedCorners = prefs.corners, savedApps = prefs.cornerApps
        prefs.paused = false; prefs.requireModifier = false
        // Test the shipping layout: brightness left, volume right, songs bottom, mute top-right.
        prefs.edges = [.left: .brightness, .right: .volume, .top: .off, .bottom: .songs]
        prefs.corners = [.topLeft: .off, .topRight: .mute, .bottomLeft: .off, .bottomRight: .off]
        engine.syncConfig()
        var clock = 1000.0
        var nextID: Int32 = 100

        func slide(x: Float, from y0: Float, to y1: Float, size: Float = 0.8) {
            nextID += 1
            for i in 0...30 {
                let y = y0 + (y1 - y0) * Float(i) / 30
                engine.feed([TouchPoint(id: nextID, x: x, y: y, size: size)], time: clock)
                clock += 0.012
                wait(0.012)
            }
            engine.feed([], time: clock); clock += 0.05
            wait(0.5)
        }
        func slideAcross(y: Float, from x0: Float, to x1: Float) {
            nextID += 1
            for i in 0...30 {
                engine.feed([TouchPoint(id: nextID, x: x0 + (x1 - x0) * Float(i) / 30, y: y, size: 0.8)], time: clock)
                clock += 0.012
                wait(0.012)
            }
            engine.feed([], time: clock); clock += 0.05
            wait(0.5)
        }
        func tap(x: Float, y: Float) {
            nextID += 1
            engine.feed([TouchPoint(id: nextID, x: x, y: y)], time: clock); clock += 0.05
            engine.feed([], time: clock); clock += 0.12
        }

        let vol0 = SystemControls.volume() ?? 0.5, muted0 = SystemControls.isMuted()
        let b0 = SystemControls.brightness() ?? 0.5

        // Right edge → volume, with the on-screen glow showing while the finger is down.
        let volUp = vol0 < 0.5
        let savedGlow = prefs.edgeGlow, savedExcluded = prefs.excludedApps
        prefs.edgeGlow = true
        nextID += 1
        var glowSeen = false
        for i in 0...30 {
            let t = Float(i) / 30
            let y: Float = volUp ? 0.2 + 0.4 * t : 0.6 - 0.4 * t
            engine.feed([TouchPoint(id: nextID, x: 0.98, y: y, size: 0.8)], time: clock)
            clock += 0.012
            wait(0.012)
            if i == 20 { glowSeen = NSApp.windows.contains { $0 is NSPanel && $0.isVisible && $0.frame.width < 40 } }
        }
        engine.feed([], time: clock); clock += 0.05
        wait(0.5)
        let vol1 = SystemControls.volume() ?? vol0
        line(volUp ? vol1 > vol0 + 0.05 : vol1 < vol0 - 0.05, "Right edge slide changes volume", String(format: "%.2f → %.2f", vol0, vol1))
        line(glowSeen, "Edge glow shows while sliding", glowSeen ? "visible" : "not visible")
        wait(1.3)
        let glowGone = !NSApp.windows.contains { $0 is NSPanel && $0.isVisible && $0.frame.width < 40 }
        line(glowGone, "Edge glow fades after release", glowGone ? "hidden" : "still visible")

        // A palm on the edge → nothing.
        wait(0.4) // let the last volume steps from the previous slide land
        let volPalm = SystemControls.volume() ?? 0
        slide(x: 0.98, from: 0.2, to: 0.6, size: 4)
        let volAfterPalm = SystemControls.volume() ?? 0
        line(abs(volAfterPalm - volPalm) < 0.001, "Palm on the edge is ignored", String(format: "%.3f → %.3f", volPalm, volAfterPalm))

        // Front app turned off → nothing.
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            prefs.excludedApps = [front]
            let volEx = SystemControls.volume() ?? 0
            slide(x: 0.98, from: 0.2, to: 0.6)
            line(abs((SystemControls.volume() ?? 0) - volEx) < 0.001, "Turned off in front app", "\(front): volume unchanged")
            prefs.excludedApps = savedExcluded
        }
        prefs.edgeGlow = savedGlow

        // Left edge → brightness.
        let bUp = b0 < 0.5
        slide(x: 0.02, from: bUp ? 0.2 : 0.6, to: bUp ? 0.6 : 0.2)
        wait(0.5)
        let b1 = SystemControls.brightness() ?? b0
        line(bUp ? b1 > b0 + 0.05 : b1 < b0 - 0.05, "Left edge slide changes brightness", String(format: "%.2f → %.2f", b0, b1))

        // Middle of the trackpad → nothing.
        let volBefore = SystemControls.volume() ?? 0
        slide(x: 0.5, from: 0.2, to: 0.6)
        line(abs((SystemControls.volume() ?? 0) - volBefore) < 0.001, "Middle slide is ignored", "volume unchanged")

        // Double-tap top-right corner → mute toggles.
        let m0 = SystemControls.isMuted()
        tap(x: 0.95, y: 0.95); tap(x: 0.95, y: 0.95)
        wait(0.5)
        let m1 = SystemControls.isMuted()
        line(m1 != m0, "Corner double-tap toggles mute", "\(m0) → \(m1)")

        // Custom layout: top edge set to volume, slid left to right.
        prefs.edges[.top] = .volume
        engine.syncConfig()
        wait(0.3)
        let vTop0 = SystemControls.volume() ?? 0
        let topUp = vTop0 < 0.5
        slideAcross(y: 0.96, from: topUp ? 0.3 : 0.7, to: topUp ? 0.7 : 0.3)
        wait(0.4)
        let vTop1 = SystemControls.volume() ?? vTop0
        line(topUp ? vTop1 > vTop0 + 0.05 : vTop1 < vTop0 - 0.05, "Top edge set to Volume works sideways", String(format: "%.2f → %.2f", vTop0, vTop1))
        prefs.edges[.top] = .off

        // Custom layout: left edge set to keyboard brightness.
        if KeyboardBacklight.isAvailable, let k0 = KeyboardBacklight.level() {
            prefs.edges[.left] = .keyboardBrightness
            engine.syncConfig()
            let kUp = k0 < 0.5
            slide(x: 0.02, from: kUp ? 0.2 : 0.6, to: kUp ? 0.6 : 0.2)
            let k1 = KeyboardBacklight.level() ?? k0
            line(kUp ? k1 > k0 + 0.05 : k1 < k0 - 0.05, "Left edge set to Keyboard Brightness works", String(format: "%.2f → %.2f", k0, k1))
            KeyboardBacklight.setLevel(k0)
            prefs.edges[.left] = .brightness
        }

        // Custom layout: bottom-left corner set to mute (toggles mute back).
        prefs.corners[.bottomLeft] = .mute
        engine.syncConfig()
        let mc0 = SystemControls.isMuted()
        tap(x: 0.05, y: 0.05); tap(x: 0.05, y: 0.05)
        wait(0.5)
        let mc1 = SystemControls.isMuted()
        line(mc1 != mc0, "Bottom-left corner set to Mute works", "\(mc0) → \(mc1)")

        // Edges and Corners map: arrow keys move in the direction pressed.
        let n = TrackpadMap.neighbor
        let arrowsOK = n(.edge(.bottom), .right) == .corner(.bottomRight)
            && n(.edge(.bottom), .up) == .edge(.top)
            && n(.edge(.left), .right) == .edge(.right)
            && n(.edge(.left), .down) == .corner(.bottomLeft)
            && n(.corner(.topLeft), .left) == nil
            && n(.corner(.topRight), .down) == .edge(.right)
        line(arrowsOK, "Map arrow keys move spatially", arrowsOK ? "all 6 moves correct" : "wrong neighbor")

        // Paused → nothing.
        prefs.paused = true; engine.syncConfig()
        let volPaused = SystemControls.volume() ?? 0
        slide(x: 0.98, from: 0.2, to: 0.6)
        line(abs((SystemControls.volume() ?? 0) - volPaused) < 0.001, "Paused ignores slides", "volume unchanged")

        // Restore everything.
        prefs.paused = savedPaused; prefs.requireModifier = savedModifier
        prefs.edges = savedEdges; prefs.corners = savedCorners; prefs.cornerApps = savedApps
        SystemControls.setVolume(vol0)
        SystemControls.setMuted(muted0)
        SystemControls.setBrightness(b0)
        wait(0.4)
        print(String(format: "Restored volume %.2f (muted: %@), brightness %.2f",
                     SystemControls.volume() ?? -1, SystemControls.isMuted() ? "yes" : "no", SystemControls.brightness() ?? -1))
        return true
    }

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--selftest") else { return false }
        func line(_ ok: Bool, _ name: String, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
        }
        func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

        line(BrimMTAvailable(), "MultitouchSupport loaded")
        let devices = BrimMTStart({ _, _, _, _ in }, nil)
        BrimMTStop()
        line(devices > 0, "Trackpads found", "\(devices)")
        line(Permissions.isTrusted, "Accessibility granted")
        DeviceWatcher.shared.start()
        line(DeviceWatcher.shared.isWatching, "Watching for trackpads being connected")

        let vol0 = SystemControls.volume()
        let muted0 = SystemControls.isMuted()
        line(vol0 != nil, "Read volume", vol0.map { String(format: "%.2f, muted: %@", $0, muted0 ? "yes" : "no") } ?? "")

        let b0 = SystemControls.brightness()
        line(b0 != nil, "Read brightness", b0.map { String(format: "%.2f", $0) } ?? "")

        if Permissions.isTrusted, let vol0 {
            SystemControls.press(vol0 > 0.5 ? .soundDown : .soundUp)
            wait(0.3)
            let vol1 = SystemControls.volume() ?? vol0
            line(abs(vol1 - vol0) > 0.001, "Volume key event", String(format: "%.3f → %.3f", vol0, vol1))
            SystemControls.press(vol0 > 0.5 ? .soundUp : .soundDown, fine: true)
            wait(0.3)
            let vol2 = SystemControls.volume() ?? vol1
            line(abs(abs(vol2 - vol1) - abs(vol1 - vol0) / 4) < 0.01, "Fine (⇧⌥) quarter step", String(format: "%.3f → %.3f", vol1, vol2))
            SystemControls.setVolume(vol0)
            SystemControls.setMuted(muted0)
        }
        if Permissions.isTrusted, let b0 {
            SystemControls.press(b0 > 0.5 ? .brightnessDown : .brightnessUp)
            wait(0.6)
            let b1 = SystemControls.brightness() ?? b0
            line(abs(b1 - b0) > 0.001, "Brightness key event", String(format: "%.3f → %.3f", b0, b1))
            SystemControls.setBrightness(b0)
            wait(0.4)
            let b2 = SystemControls.brightness() ?? b0
            line(abs(b2 - b0) < 0.01, "Direct brightness set", String(format: "back to %.3f", b2))
        }
        line(BrimHapticActuate(6), "Force Touch actuator")
        print("INFO  Update feed: \(AppConfig.updateFeedURL?.absoluteString ?? "off")")
        print(String(format: "Restored volume %.2f (muted: %@), brightness %.2f",
                     SystemControls.volume() ?? -1, SystemControls.isMuted() ? "yes" : "no", SystemControls.brightness() ?? -1))
        return true
    }
}
