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
        let savedPaused = prefs.paused, savedSwap = prefs.swapSides, savedModifier = prefs.requireModifier
        prefs.paused = false; prefs.swapSides = false; prefs.requireModifier = false
        engine.syncConfig()
        var clock = 1000.0
        var nextID: Int32 = 100

        func slide(x: Float, from y0: Float, to y1: Float) {
            nextID += 1
            for i in 0...30 {
                let y = y0 + (y1 - y0) * Float(i) / 30
                engine.feed([TouchPoint(id: nextID, x: x, y: y)], time: clock)
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

        // Right edge → volume.
        let volUp = vol0 < 0.5
        slide(x: 0.98, from: volUp ? 0.2 : 0.6, to: volUp ? 0.6 : 0.2)
        let vol1 = SystemControls.volume() ?? vol0
        line(volUp ? vol1 > vol0 + 0.05 : vol1 < vol0 - 0.05, "Right edge slide changes volume", String(format: "%.2f → %.2f", vol0, vol1))

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

        // Paused → nothing.
        prefs.paused = true; engine.syncConfig()
        let volPaused = SystemControls.volume() ?? 0
        slide(x: 0.98, from: 0.2, to: 0.6)
        line(abs((SystemControls.volume() ?? 0) - volPaused) < 0.001, "Paused ignores slides", "volume unchanged")

        // Restore everything.
        prefs.paused = savedPaused; prefs.swapSides = savedSwap; prefs.requireModifier = savedModifier
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
        Licensing.shared.evaluate()
        print("INFO  License state: \(Licensing.shared.state)")
        print("INFO  Update feed: \(AppConfig.updateFeedURL?.absoluteString ?? "off")")
        print(String(format: "Restored volume %.2f (muted: %@), brightness %.2f",
                     SystemControls.volume() ?? -1, SystemControls.isMuted() ? "yes" : "no", SystemControls.brightness() ?? -1))
        return true
    }
}
