import AppKit
import AudioToolbox
import CSlidebarPrivate
import CoreAudio

/// Hardware "aux" keys understood by macOS (from IOKit's ev_keymap.h).
enum MediaKey: Int32 {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case play = 16
    case next = 17
    case previous = 18
}

/// Changes volume and brightness by sending the same key events the keyboard sends,
/// so macOS shows its own on-screen display and honors ⇧⌥ quarter steps.
enum SystemControls {
    // MARK: Key events

    static func press(_ key: MediaKey, fine: Bool = false) {
        var flags: NSEvent.ModifierFlags = []
        if fine { flags = [.shift, .option] }
        post(key, down: true, flags: flags)
        post(key, down: false, flags: flags)
    }

    private static func post(_ key: MediaKey, down: Bool, flags: NSEvent.ModifierFlags) {
        let stateBits: Int = down ? 0xA : 0xB
        let data1 = (Int(key.rawValue) << 16) | (stateBits << 8)
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(stateBits << 8)).union(flags),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: Volume (CoreAudio)

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// Output volume from 0 to 1, or nil if the device has no volume control.
    static func volume() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    static func setVolume(_ value: Float) {
        guard let device = defaultOutputDevice() else { return }
        var level = Float32(min(max(value, 0), 1))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return }
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level)
        if level > 0, isMuted() { setMuted(false) }
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var value = UInt32(muted ? 1 : 0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return }
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func isMuted() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    // MARK: Brightness (DisplayServices)

    /// The built-in display, falling back to the main display.
    static func builtInDisplay() -> CGDirectDisplayID {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
    }

    /// Display brightness from 0 to 1, or nil if it can't be read.
    static func brightness() -> Float? {
        var value: Float = 0
        return SlidebarGetBrightness(builtInDisplay(), &value) ? value : nil
    }

    @discardableResult
    static func setBrightness(_ value: Float) -> Bool {
        SlidebarSetBrightness(builtInDisplay(), value)
    }
}

// MARK: - Shortcuts and system actions

extension SystemControls {
    /// Virtual key codes (Carbon kVK_*) used by Slidebar's actions.
    enum Key: CGKeyCode {
        case tab = 48, z = 6, grave = 50, space = 49, q = 12
        /// A key nothing uses, for checks that need a key press.
        case f20 = 90
    }

    /// When Slidebar last pressed a shortcut itself (system uptime), so it isn't mistaken for typing.
    private(set) static var lastShortcutTime: TimeInterval = -.infinity

    /// Presses a keyboard shortcut, like the user typing it.
    static func shortcut(_ key: Key, _ flags: CGEventFlags) {
        lastShortcutTime = ProcessInfo.processInfo.systemUptime
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    static func openSystemApp(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
    }

    static var hasScreenshotApp: Bool { FileManager.default.fileExists(atPath: "/System/Applications/Utilities/Screenshot.app") }

    /// Locks the screen immediately, the same way the Apple menu's Lock Screen does.
    static func lockScreen() {
        typealias Lock = @convention(c) () -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: Lock.self)()
        } else {
            shortcut(.q, [.maskCommand, .maskControl])
        }
    }

    static func sleepDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    /// Opens an app like clicking it in the Dock. Asking a running app to open only brings it to the
    /// front, which shows nothing when its window is closed (Telegram keeps running with no window)
    /// or on another desktop, so a running app gets a click on its Dock icon instead.
    ///
    /// The click alone isn't enough when macOS is set not to follow apps to their desktop: an app
    /// that doesn't raise its own window (Telegram) may stay out of sight, or the desktop switch may
    /// hand focus to whatever was last used there. So its window is brought forward first, unseen,
    /// and the click then makes a single switch straight to it.
    static func openApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            _ = SlidebarFocusFrontWindow(app.processIdentifier)
            if DockIcon.click(appAt: url) { return }
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
