import AppKit
import BrimCore
import CBrimPrivate
import Combine

/// Live values shown in the menu, plus overall status.
final class LiveState: ObservableObject {
    static let shared = LiveState()

    enum Status: Equatable {
        case ready, needsAccess, noTrackpad, paused

        var title: String {
            switch self {
            case .ready: return "Ready"
            case .needsAccess: return "Needs Access"
            case .noTrackpad: return "No Trackpad"
            case .paused: return "Paused"
            }
        }
    }

    @Published var brightness: Float?
    @Published var volume: Float?
    @Published var muted = false
    @Published var trusted = Permissions.isTrusted
    @Published var deviceCount = 0
    /// Bumped every time the user completes a slide (used by the setup guide).
    @Published var slideCount = 0
    /// The control currently being slid, for highlighting in the menu.
    @Published var activeControl: EdgeControl?

    var status: Status {
        if Prefs.shared.paused { return .paused }
        if deviceCount == 0 { return .noTrackpad }
        if !trusted { return .needsAccess }
        return .ready
    }

    func refreshLevels() {
        let b = SystemControls.brightness()
        let v = SystemControls.volume()
        let m = SystemControls.isMuted()
        if b != brightness { brightness = b }
        if v != volume { volume = v }
        if m != muted { muted = m }
    }

    func refreshTrust() {
        let t = Permissions.isTrusted
        if t != trusted { trusted = t }
    }
}

/// Connects raw trackpad frames to the recognizer and performs its actions.
final class EdgeEngine {
    static let shared = EdgeEngine()

    private var recognizer = EdgeRecognizer()
    private let prefs = Prefs.shared
    private let live = LiveState.shared
    private var cancellables = Set<AnyCancellable>()
    private var cursorFrozen = false
    private var brightnessKeysWork: Bool?
    private var refreshScheduled = false

    private init() {
        // Keep the recognizer's config in sync with settings.
        prefs.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.syncConfig() }
            .store(in: &cancellables)
        live.$trusted
            .removeDuplicates()
            .sink { [weak self] _ in self?.brightnessKeysWork = nil }
            .store(in: &cancellables)
        syncConfig()
    }

    func syncConfig() {
        var c = EdgeConfig()
        c.edgeWidth = Float(prefs.edgeWidth)
        c.sensitivity = Float(prefs.sensitivity)
        c.swapSides = prefs.swapSides
        c.bottomQuarterOnly = prefs.bottomQuarterOnly
        c.quickMute = prefs.quickMute
        c.mediaStrip = prefs.mediaStrip
        c.tapToPlay = prefs.tapToPlay
        c.freezeCursor = prefs.freezeCursor
        c.fineControl = prefs.fineControl
        recognizer.config = c
    }

    // MARK: Lifecycle

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let count = BrimMTStart({ touches, count, timestamp, context in
            guard let context else { return }
            var points: [TouchPoint] = []
            if let touches, count > 0 {
                points.reserveCapacity(Int(count))
                for t in UnsafeBufferPointer(start: touches, count: Int(count)) where t.state == 3 || t.state == 4 {
                    points.append(TouchPoint(id: t.identifier, x: t.x, y: t.y))
                }
            }
            let engine = Unmanaged<EdgeEngine>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { engine.handle(points, time: timestamp) }
        }, context)
        live.deviceCount = Int(count)
        NSLog("Brim: listening on \(count) trackpad(s)")
    }

    func restart() {
        releaseCursor()
        recognizer = EdgeRecognizer(config: recognizer.config)
        start()
    }

    func stop() {
        BrimMTStop()
        releaseCursor()
    }

    // MARK: Frames

    private func handle(_ touches: [TouchPoint], time: Double) {
        let flags = NSEvent.modifierFlags
        var allowed = !prefs.paused
        if prefs.requireModifier {
            allowed = allowed && (flags.contains(.function) || flags.contains(.option))
        }
        let context = EdgeContext(gestureAllowed: allowed, fineKeysHeld: flags.contains([.shift, .option]))
        let actions = recognizer.process(touches, time: time, context: context)
        for action in actions { perform(action) }
        if !recognizer.isTracking, live.activeControl != nil {
            live.activeControl = nil
        }
    }

    private func perform(_ action: EdgeAction) {
        switch action {
        case .freezeCursor:
            freezeCursor()
        case .releaseCursor:
            if live.activeControl != nil { live.slideCount += 1 }
            releaseCursor()
        case .slideBegan(let control):
            live.activeControl = control
        case .step(let control, let up, let fine):
            switch control {
            case .volume: stepVolume(up: up, fine: fine)
            case .brightness: stepBrightness(up: up, fine: fine)
            }
            Haptics.tick(prefs.haptics)
            scheduleRefresh()
        case .toggleMute:
            if live.trusted {
                SystemControls.press(.mute)
            } else {
                SystemControls.setMuted(!SystemControls.isMuted())
            }
            Haptics.tick(prefs.haptics)
            scheduleRefresh()
        case .playPause:
            SystemControls.press(.play)
            Haptics.tick(prefs.haptics)
        case .nextTrack:
            SystemControls.press(.next)
            Haptics.tick(prefs.haptics)
        case .previousTrack:
            SystemControls.press(.previous)
            Haptics.tick(prefs.haptics)
        }
    }

    // MARK: Controls

    private func stepVolume(up: Bool, fine: Bool) {
        if live.trusted {
            SystemControls.press(up ? .soundUp : .soundDown, fine: fine)
        } else {
            // Without Accessibility we can still set the level directly (no on-screen display).
            let current = SystemControls.volume() ?? 0
            let delta: Float = (fine ? 1 / 64 : 1 / 16) * (up ? 1 : -1)
            SystemControls.setVolume(current + delta)
        }
    }

    private func stepBrightness(up: Bool, fine: Bool) {
        let delta: Float = (fine ? 1 / 64 : 1 / 16) * (up ? 1 : -1)
        guard live.trusted, brightnessKeysWork != false else {
            setBrightnessDirectly(delta)
            return
        }
        let before = SystemControls.brightness()
        SystemControls.press(up ? .brightnessUp : .brightnessDown, fine: fine)

        // Some setups ignore synthetic brightness keys. Check once and fall back if so.
        guard brightnessKeysWork == nil, let before, up ? before < 0.98 : before > 0.02 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.brightnessKeysWork == nil else { return }
            let after = SystemControls.brightness() ?? before
            if abs(after - before) < 0.002 {
                NSLog("Brim: brightness keys had no effect, switching to direct control")
                self.brightnessKeysWork = false
                self.setBrightnessDirectly(delta)
            } else {
                self.brightnessKeysWork = true
            }
        }
    }

    private func setBrightnessDirectly(_ delta: Float) {
        guard let current = SystemControls.brightness() else { return }
        SystemControls.setBrightness(current + delta)
    }

    // MARK: Cursor

    private func freezeCursor() {
        guard !cursorFrozen else { return }
        CGAssociateMouseAndMouseCursorPosition(0)
        cursorFrozen = true
    }

    private func releaseCursor() {
        guard cursorFrozen else { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        cursorFrozen = false
    }

    // MARK: Refresh

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.refreshScheduled = false
            self?.live.refreshLevels()
        }
    }
}
