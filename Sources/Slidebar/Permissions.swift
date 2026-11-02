import AppKit
import ApplicationServices

/// Accessibility access. Slidebar works without it, but needs it to press keys for you
/// (volume and brightness keys with the on-screen display, media keys, shortcuts).
enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (only appears once per app identity).
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// One action, one surface: the system prompt the first time, System Settings after that.
    static func ask() {
        let prefs = Prefs.shared
        if prefs.didPromptAccess {
            openAccessibilitySettings()
        } else {
            prefs.didPromptAccess = true
            requestAccess()
        }
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
