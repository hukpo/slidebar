import AppKit
import CBrimPrivate

/// `Brim --selftest`: checks the system hooks Brim relies on, then restores every level it touched.
enum SelfTest {
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
        print(String(format: "Restored volume %.2f (muted: %@), brightness %.2f",
                     SystemControls.volume() ?? -1, SystemControls.isMuted() ? "yes" : "no", SystemControls.brightness() ?? -1))
        return true
    }
}
