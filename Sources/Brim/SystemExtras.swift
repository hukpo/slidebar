import AppKit
import AudioToolbox
import CoreAudio
import IOKit.pwr_mgt
import SwiftUI

// MARK: - Microphone

/// The default input device's volume and mute, through CoreAudio.
enum Microphone {
    private static func device() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)

    private static func settable(_ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(device, &address) else { return false }
        var ok: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &ok) == noErr && ok.boolValue
    }

    static var hasVolume: Bool {
        guard let d = device() else { return false }
        return settable(d, &volumeAddress)
    }

    static func volume() -> Float? {
        guard let d = device(), AudioObjectHasProperty(d, &volumeAddress) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(d, &volumeAddress, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func setVolume(_ value: Float) {
        guard let d = device(), settable(d, &volumeAddress) else { return }
        var v = Float32(min(max(value, 0), 1))
        AudioObjectSetPropertyData(d, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    private static let savedVolumeKey = "micVolumeBeforeMute"

    static func isMuted() -> Bool {
        guard let d = device() else { return false }
        if AudioObjectHasProperty(d, &muteAddress) {
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(d, &muteAddress, 0, nil, &size, &value) == noErr { return value != 0 }
        }
        return (volume() ?? 1) == 0
    }

    static func setMuted(_ muted: Bool) {
        guard let d = device() else { return }
        if settable(d, &muteAddress) {
            var value = UInt32(muted ? 1 : 0)
            AudioObjectSetPropertyData(d, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        } else if muted {
            // No mute switch on this device: remember the level and turn it all the way down.
            UserDefaults.standard.set(volume() ?? 0.5, forKey: savedVolumeKey)
            setVolume(0)
        } else {
            setVolume(UserDefaults.standard.object(forKey: savedVolumeKey) as? Float ?? 0.5)
        }
    }
}

// MARK: - Night Shift

/// Night Shift warmth through CoreBrightness's CBBlueLightClient (private). Guarded throughout.
enum NightShift {
    private typealias GetStrength = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> Bool
    private typealias SetStrength = @convention(c) (AnyObject, Selector, Float, Bool) -> Bool
    private typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool) -> Bool
    private typealias GetStatus = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool

    private static let client: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    private static func imp<T>(_ name: String, _ type: T.Type) -> T? {
        guard let client, client.responds(to: NSSelectorFromString(name)) else { return nil }
        return unsafeBitCast(client.method(for: NSSelectorFromString(name)), to: type)
    }

    static var isAvailable: Bool {
        imp("getStrength:", GetStrength.self) != nil && imp("setStrength:commit:", SetStrength.self) != nil
            && imp("setEnabled:", SetEnabled.self) != nil && imp("getBlueLightStatus:", GetStatus.self) != nil
    }

    /// True while Night Shift is tinting the screen.
    static var isActive: Bool {
        guard let client, let get = imp("getBlueLightStatus:", GetStatus.self) else { return false }
        let status = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        defer { status.deallocate() }
        status.initializeMemory(as: UInt8.self, repeating: 0, count: 64)
        guard get(client, NSSelectorFromString("getBlueLightStatus:"), status) else { return false }
        return status.load(as: Bool.self) // first field: active
    }

    /// Warmth from 0 to 1; 0 while Night Shift is off.
    static func level() -> Float? {
        guard let client, let get = imp("getStrength:", GetStrength.self) else { return nil }
        guard isActive else { return 0 }
        var strength: Float = 0
        return get(client, NSSelectorFromString("getStrength:"), &strength) ? strength : nil
    }

    /// The stored warmth even while Night Shift is off (for putting things back exactly).
    static func rawStrength() -> Float? {
        guard let client, let get = imp("getStrength:", GetStrength.self) else { return nil }
        var strength: Float = 0
        return get(client, NSSelectorFromString("getStrength:"), &strength) ? strength : nil
    }

    /// Restores a saved state exactly.
    static func restore(active: Bool, strength: Float) {
        guard let client, let set = imp("setStrength:commit:", SetStrength.self),
              let enable = imp("setEnabled:", SetEnabled.self) else { return }
        _ = set(client, NSSelectorFromString("setStrength:commit:"), strength, true)
        if isActive != active { _ = enable(client, NSSelectorFromString("setEnabled:"), active) }
    }

    /// Sets the warmth, turning Night Shift on (or off at zero).
    static func setLevel(_ value: Float) {
        guard let client, let set = imp("setStrength:commit:", SetStrength.self),
              let enable = imp("setEnabled:", SetEnabled.self) else { return }
        let v = min(max(value, 0), 1)
        if v > 0, !isActive { _ = enable(client, NSSelectorFromString("setEnabled:"), true) }
        _ = set(client, NSSelectorFromString("setStrength:commit:"), max(v, 0.01), true)
        if v == 0, isActive { _ = enable(client, NSSelectorFromString("setEnabled:"), false) }
    }
}

// MARK: - Keep awake

/// Keeps the Mac and its display awake until turned off, with a standard power assertion.
enum KeepAwake {
    private static var assertion: IOPMAssertionID = 0

    static var isOn: Bool { assertion != 0 }

    static func toggle() -> Bool {
        if isOn {
            IOPMAssertionRelease(assertion)
            assertion = 0
        } else {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Brim: Keep Mac Awake" as CFString, &id)
            if result == kIOReturnSuccess { assertion = id }
        }
        LiveState.shared.keepingAwake = isOn
        return isOn
    }
}

// MARK: - Shortcuts

/// The user's Shortcuts, through the `shortcuts` command-line tool.
enum UserShortcuts {
    /// Names of the user's shortcuts, read off the main thread.
    static func list(_ completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let names = (try? run(["list"]))?
                .split(separator: "\n").map(String.init).filter { !$0.isEmpty } ?? []
            DispatchQueue.main.async { completion(names) }
        }
    }

    static func run(name: String) {
        DispatchQueue.global(qos: .userInitiated).async { _ = try? run(["run", name]) }
    }

    private static func run(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Confirmation toast

/// A brief on-screen confirmation for toggles ("Microphone Muted"), styled like the system HUD.
final class Toast {
    static let shared = Toast()

    final class Model: ObservableObject {
        @Published var icon = "checkmark"
        @Published var text = ""
        @Published var visible = false
    }

    private let model = Model()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ text: String, icon: String) {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = NSSize(width: 300, height: 64)
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.14,
                              width: size.width, height: size.height), display: false)
        model.icon = icon
        model.text = text
        panel.orderFrontRegardless()
        withAnimation(.easeOut(duration: 0.18)) { model.visible = true }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeIn(duration: 0.3)) { self.model.visible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                if self?.model.visible == false { self?.panel?.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ToastView(model: model))
        return panel
    }
}

private struct ToastView: View {
    @ObservedObject var model: Toast.Model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.icon)
                .font(.system(size: 17, weight: .semibold))
            Text(model.text)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .opacity(model.visible ? 1 : 0)
        .scaleEffect(model.visible || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0.96)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
