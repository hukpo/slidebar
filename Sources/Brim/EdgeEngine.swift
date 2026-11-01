import AppKit
import BrimCore
import CBrimPrivate
import Combine

/// Live values shown in the menu, plus overall status.
final class LiveState: ObservableObject {
    static let shared = LiveState()

    enum Status: Equatable {
        case ready, noTrackpad, paused

        var title: String {
            switch self {
            case .ready: return "Ready"
            case .noTrackpad: return "No Trackpad"
            case .paused: return "Paused"
            }
        }
    }

    @Published var brightness: Float?
    @Published var volume: Float?
    @Published var keyboardBrightness: Float?
    @Published var micVolume: Float?
    @Published var nightShift: Float?
    @Published var muted = false
    @Published var micMuted = false
    @Published var keepingAwake = false
    @Published var trusted = Permissions.isTrusted
    @Published var deviceCount = 0
    /// Bumped every time the user completes a slide (used by the setup guide).
    @Published var slideCount = 0
    /// The edge currently being slid, for highlighting in the menu.
    @Published var activeSide: EdgeSide?
    /// True right after setup, when the menu opens to show where Brim lives.
    @Published var showWelcome = false
    /// Set when a gesture asked for something that needs Accessibility, so the menu can explain.
    @Published var blockedAction: String?

    var status: Status {
        if Prefs.shared.paused { return .paused }
        if deviceCount == 0 { return .noTrackpad }
        return .ready
    }

    /// Accessibility is optional; mention it until the user allows it or says no thanks.
    var showAccessNotice: Bool { !trusted && !Prefs.shared.accessNoticeDismissed }

    func level(of function: EdgeFunction) -> Float? {
        switch function {
        case .brightness: return brightness
        case .volume: return volume
        case .keyboardBrightness: return keyboardBrightness
        case .micVolume: return micVolume
        case .nightShift: return nightShift
        default: return nil
        }
    }

    func refreshLevels() {
        let b = SystemControls.brightness()
        let v = SystemControls.volume()
        let m = SystemControls.isMuted()
        if b != brightness { brightness = b }
        if v != volume { volume = v }
        if m != muted { muted = m }
        let edges = Prefs.shared.edges.values
        if edges.contains(.keyboardBrightness) {
            let k = KeyboardBacklight.level()
            if k != keyboardBrightness { keyboardBrightness = k }
        }
        if edges.contains(.micVolume) {
            let mv = Microphone.volume()
            if mv != micVolume { micVolume = mv }
        }
        if edges.contains(.nightShift) {
            let n = NightShift.level()
            if n != nightShift { nightShift = n }
        }
        if Prefs.shared.corners.values.contains(.muteMicrophone) {
            let mm = Microphone.isMuted()
            if mm != micMuted { micMuted = mm }
        }
    }

    func refreshTrust() {
        let t = Permissions.isTrusted
        if t != trusted {
            trusted = t
            if t { blockedAction = nil }
        }
    }
}

/// Connects raw trackpad frames to the recognizer and performs what the user assigned.
final class EdgeEngine {
    static let shared = EdgeEngine()

    private var recognizer = EdgeRecognizer()
    private let prefs = Prefs.shared
    private let live = LiveState.shared
    private var cancellables = Set<AnyCancellable>()
    private var cursorFrozen = false
    private var brightnessKeysWork: Bool?
    private var refreshScheduled = false
    /// The level we expect after the steps sent so far in this slide (key events land asynchronously).
    private var expectedLevel: Float?
    /// Steps collected toward the next tab or undo action.
    private var pendingSteps = 0
    /// How things were when the current slide began, to put back if it turns out to be a palm.
    private var slideStartLevel: Float?
    private var slideStartMuted = false
    /// Tab or undo actions sent in this slide (forward minus back).
    private var slideActions = 0

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
        c.bottomQuarterOnly = prefs.bottomQuarterOnly
        c.freezeCursor = prefs.freezeCursor
        c.fineControl = prefs.fineControl
        c.palmRejection = prefs.palmRejection
        c.edges = Dictionary(uniqueKeysWithValues: EdgeSide.allCases.map { ($0, prefs.edge($0).kind) })
        c.corners = Set(Corner.allCases.filter { prefs.cornerIsActive($0) })
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
                    points.append(TouchPoint(id: t.identifier, x: t.x, y: t.y, size: t.size, major: t.majorAxis))
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

    /// Feeds synthetic frames through the same path as real trackpad frames (used by --simulate).
    func feed(_ touches: [TouchPoint], time: Double) { handle(touches, time: time) }

    private func handle(_ touches: [TouchPoint], time: Double) {
        let flags = NSEvent.modifierFlags
        var allowed = !prefs.paused
        if prefs.requireModifier {
            allowed = allowed && (flags.contains(.function) || flags.contains(.option))
        }
        // Like macOS's own palm protection: ignore new edge touches right after typing.
        let typing = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) < 1.0
        let context = EdgeContext(gestureAllowed: allowed && !typing,
                                  fineKeysHeld: flags.contains([.shift, .option]),
                                  buttonHeld: NSEvent.pressedMouseButtons != 0)
        let actions = recognizer.process(touches, time: time, context: context)
        for action in actions { perform(action) }
        if !recognizer.isTracking, live.activeSide != nil {
            live.activeSide = nil
        }
    }

    private func perform(_ action: EdgeAction) {
        switch action {
        case .freezeCursor:
            freezeCursor()

        case .releaseCursor:
            if live.activeSide != nil {
                live.slideCount += 1
                EdgeGlow.shared.hide()
            }
            expectedLevel = nil
            releaseCursor()

        case .slideBegan(let side):
            let function = prefs.edge(side)
            live.activeSide = side
            pendingSteps = 0
            expectedLevel = currentLevel(function)
            slideStartLevel = expectedLevel
            slideStartMuted = live.muted
            slideActions = 0
            if prefs.edgeGlow, function.hasLevel, let level = expectedLevel {
                EdgeGlow.shared.show(function, on: side, level: level, muted: function == .volume && live.muted)
            }

        case .slideCancelled(let side):
            undoSlide(prefs.edge(side), side: side)

        case .step(let side, let up, let fine):
            step(prefs.edge(side), side: side, up: up, fine: fine)

        case .swipe(let side, let forward):
            let function = prefs.edge(side)
            swipe(function, forward: forward)

        case .doubleTap(let side):
            if prefs.edge(side) == .songs && prefs.tapToPlay {
                run(needsAccess: true, name: "Play and pause") { SystemControls.press(.play) }
            }

        case .cornerDoubleTap(let corner):
            cornerAction(corner)
        }
    }

    // MARK: Edge functions

    private func step(_ function: EdgeFunction, side: EdgeSide, up: Bool, fine: Bool) {
        if function.hasLevel {
            let delta: Float = (fine ? 1 / 64 : 1 / 16) * (up ? 1 : -1)
            let before = expectedLevel ?? currentLevel(function) ?? 0.5
            let after = min(max(before + delta, 0), 1)
            expectedLevel = after
            switch function {
            case .volume: stepVolume(up: up, fine: fine)
            case .brightness: stepBrightness(up: up, fine: fine)
            case .keyboardBrightness: KeyboardBacklight.setLevel(after)
            case .micVolume: Microphone.setVolume(after)
            case .nightShift: NightShift.setLevel(after)
            default: break
            }
            // A tick per step, a firmer bump on reaching 0% or 100%, then silence at the limit.
            if after != before {
                if after == 0 || after == 1 { Haptics.bump(prefs.haptics) } else { Haptics.tick(prefs.haptics) }
            }
            if prefs.edgeGlow { EdgeGlow.shared.update(level: after, muted: false) }
            scheduleRefresh()
            return
        }

        // Stepping actions fire once every few steps, and reverse cleanly if the finger turns back.
        if (pendingSteps > 0) != up { pendingSteps = 0 }
        pendingSteps += up ? 1 : -1
        guard abs(pendingSteps) >= function.stepsPerAction else { return }
        pendingSteps = 0

        run(needsAccess: function.needsAccess, name: function.blockedName) {
            switch function {
            case .tabs: SystemControls.shortcut(.tab, up ? .maskControl : [.maskControl, .maskShift])
            case .undo: SystemControls.shortcut(.z, up ? [.maskCommand, .maskShift] : .maskCommand)
            default: return
            }
            slideActions += up ? 1 : -1
            Haptics.tick(prefs.haptics)
        }
    }

    /// A palm moved the slider: quietly put everything back the way it was.
    private func undoSlide(_ function: EdgeFunction, side: EdgeSide) {
        EdgeGlow.shared.hide()
        live.activeSide = nil
        if function.hasLevel, let level = slideStartLevel {
            let muted = slideStartMuted
            // After the key presses already sent have landed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                switch function {
                case .volume:
                    SystemControls.setVolume(level)
                    SystemControls.setMuted(muted)
                case .brightness: SystemControls.setBrightness(level)
                case .keyboardBrightness: KeyboardBacklight.setLevel(level)
                case .micVolume: Microphone.setVolume(level)
                case .nightShift: NightShift.setLevel(level)
                default: break
                }
                self?.scheduleRefresh()
            }
        } else if slideActions != 0, live.trusted {
            let back = slideActions < 0
            for _ in 0..<abs(slideActions) {
                switch function {
                case .tabs: SystemControls.shortcut(.tab, back ? .maskControl : [.maskControl, .maskShift])
                case .undo: SystemControls.shortcut(.z, back ? [.maskCommand, .maskShift] : .maskCommand)
                default: break
                }
            }
        }
        slideActions = 0
        slideStartLevel = nil
        pendingSteps = 0
    }

    private func swipe(_ function: EdgeFunction, forward: Bool) {
        run(needsAccess: function.needsAccess, name: function.blockedName) {
            switch function {
            case .songs: SystemControls.press(forward ? .next : .previous)
            case .windows: SystemControls.shortcut(.grave, forward ? .maskCommand : [.maskCommand, .maskShift])
            default: return
            }
            Haptics.tick(prefs.haptics)
        }
    }

    private func cornerAction(_ corner: Corner) {
        let function = prefs.corner(corner)
        run(needsAccess: function.needsAccess, name: function.blockedName) {
            switch function {
            case .off: return
            case .mute:
                if live.trusted { SystemControls.press(.mute) } else { SystemControls.setMuted(!SystemControls.isMuted()) }
                scheduleRefresh()
            case .muteMicrophone:
                let muted = !Microphone.isMuted()
                Microphone.setMuted(muted)
                live.micMuted = Microphone.isMuted()
                Toast.shared.show(muted ? "Microphone Muted" : "Microphone On", icon: muted ? "mic.slash.fill" : "mic.fill")
            case .playPause: SystemControls.press(.play)
            case .nextSong: SystemControls.press(.next)
            case .previousSong: SystemControls.press(.previous)
            case .keepAwake:
                let on = KeepAwake.toggle()
                Toast.shared.show(on ? "Keeping Your Mac Awake" : "Your Mac Can Sleep Again", icon: on ? "cup.and.saucer.fill" : "moon.zzz")
            case .lockScreen: SystemControls.lockScreen()
            case .sleepDisplay: SystemControls.sleepDisplay()
            case .screenshot: SystemControls.openSystemApp("/System/Applications/Utilities/Screenshot.app")
            case .spotlight: SystemControls.shortcut(.space, .maskCommand)
            case .emoji: SystemControls.shortcut(.space, [.maskCommand, .maskControl])
            case .runShortcut:
                if let name = prefs.cornerShortcuts[corner] {
                    UserShortcuts.run(name: name)
                    Toast.shared.show("Running \u{201C}\(name)\u{201D}", icon: "square.2.layers.3d.fill")
                }
            case .openApp:
                if let id = prefs.cornerApps[corner] { SystemControls.openApp(bundleID: id) }
            }
            Haptics.tick(prefs.haptics)
        }
    }

    /// Runs an action, or explains in the menu why it can't run yet.
    private func run(needsAccess: Bool, name: String, _ body: () -> Void) {
        guard !needsAccess || live.trusted else {
            live.blockedAction = name
            Haptics.bump(prefs.haptics)
            return
        }
        body()
    }

    // MARK: Levels

    private func currentLevel(_ function: EdgeFunction) -> Float? {
        switch function {
        case .volume: return SystemControls.volume()
        case .brightness: return SystemControls.brightness()
        case .keyboardBrightness: return KeyboardBacklight.level()
        case .micVolume: return Microphone.volume()
        case .nightShift: return NightShift.level()
        default: return nil
        }
    }

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
