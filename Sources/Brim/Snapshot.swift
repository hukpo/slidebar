import AppKit
import SwiftUI

/// `Brim --snapshot <dir> [light|dark]` renders each screen to a PNG (for docs and visual checks).
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1])
        let dark = args.contains("dark")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let suffix = dark ? "-dark" : ""
        LiveState.shared.refreshLevels()
        LiveState.shared.deviceCount = max(LiveState.shared.deviceCount, 1)

        render(MenuView(), to: dir.appendingPathComponent("menu\(suffix).png"))
        render(SettingsPage(page: .constant(.settings)).frame(width: 330), to: dir.appendingPathComponent("settings\(suffix).png"))
        render(SetupView(onDone: {}), to: dir.appendingPathComponent("setup\(suffix).png"))
        render(LicenseView(onClose: {}), to: dir.appendingPathComponent("license\(suffix).png"))
        return true
    }

    private static func render<V: View>(_ view: V, to url: URL) {
        let hosting = NSHostingView(rootView: view.background(VisualEffect()))
        hosting.frame.size = hosting.fittingSize
        let window = KeyWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        // Render as an active window so switches show their "on" color.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        window.makeKey()
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
        print("wrote \(url.path)")
    }
}

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
