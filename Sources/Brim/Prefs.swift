import AppKit
import BrimCore
import Combine
import ServiceManagement

enum HapticStrength: String, CaseIterable, Identifiable {
    case off, light, medium, strong
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// All user settings, persisted to UserDefaults.
final class Prefs: ObservableObject {
    static let shared = Prefs()

    static let sensitivityRange: ClosedRange<Double> = 0.5...3.0
    static let sensitivityStep = 0.25
    static let edgeWidthRange: ClosedRange<Double> = 0.02...0.12
    static let edgeWidthStep = 0.01

    private let defaults = UserDefaults.standard

    // Main menu
    @Published var haptics: HapticStrength { didSet { defaults.set(haptics.rawValue, forKey: Keys.haptics) } }
    @Published var tapToPlay: Bool { didSet { defaults.set(tapToPlay, forKey: Keys.tapToPlay) } }
    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: Keys.sensitivity) } }
    @Published var edgeWidth: Double { didSet { defaults.set(edgeWidth, forKey: Keys.edgeWidth) } }

    // Edges and corners
    @Published var edges: [EdgeSide: EdgeFunction] {
        didSet { for (side, f) in edges { defaults.set(f.rawValue, forKey: Keys.edge(side)) } }
    }
    @Published var corners: [Corner: CornerFunction] {
        didSet { for (c, f) in corners { defaults.set(f.rawValue, forKey: Keys.corner(c)) } }
    }
    /// For corners set to "Open an App": the app's bundle ID.
    @Published var cornerApps: [Corner: String] {
        didSet { for c in Corner.allCases { defaults.set(cornerApps[c], forKey: Keys.cornerApp(c)) } }
    }
    /// For corners set to "Run a Shortcut": the shortcut's name.
    @Published var cornerShortcuts: [Corner: String] {
        didSet { for c in Corner.allCases { defaults.set(cornerShortcuts[c], forKey: Keys.cornerShortcut(c)) } }
    }

    // Settings page
    @Published var bottomQuarterOnly: Bool { didSet { defaults.set(bottomQuarterOnly, forKey: Keys.bottomQuarterOnly) } }
    @Published var requireModifier: Bool { didSet { defaults.set(requireModifier, forKey: Keys.requireModifier) } }
    @Published var freezeCursor: Bool { didSet { defaults.set(freezeCursor, forKey: Keys.freezeCursor) } }
    @Published var fineControl: Bool { didSet { defaults.set(fineControl, forKey: Keys.fineControl) } }
    @Published var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            NSApp.appearance = appearance.nsAppearance
        }
    }

    // State
    @Published var autoUpdate: Bool { didSet { defaults.set(autoUpdate, forKey: Keys.autoUpdate) } }
    @Published var palmRejection: Bool { didSet { defaults.set(palmRejection, forKey: Keys.palmRejection) } }
    @Published var edgeGlow: Bool { didSet { defaults.set(edgeGlow, forKey: Keys.edgeGlow) } }
    /// Bundle IDs of apps where edge gestures are off.
    @Published var excludedApps: [String] { didSet { defaults.set(excludedApps, forKey: Keys.excludedApps) } }

    // State
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: Keys.paused) } }
    @Published var hasCompletedSetup: Bool { didSet { defaults.set(hasCompletedSetup, forKey: Keys.setupDone) } }
    /// The system Accessibility prompt only ever appears once; after that we open System Settings instead.
    @Published var didPromptAccess: Bool { didSet { defaults.set(didPromptAccess, forKey: Keys.didPromptAccess) } }
    /// The user chose to use Brim without Accessibility; stop mentioning it in the menu.
    @Published var accessNoticeDismissed: Bool { didSet { defaults.set(accessNoticeDismissed, forKey: Keys.accessNoticeDismissed) } }
    @Published private(set) var openAtLogin: Bool = false

    private enum Keys {
        static let haptics = "haptics"
        static let quickMute = "quickMute"       // legacy, read once for migration
        static let mediaStrip = "mediaStrip"     // legacy
        static let swapSides = "swapSides"       // legacy
        static func edge(_ side: EdgeSide) -> String { "edge.\(side.rawValue)" }
        static func corner(_ c: Corner) -> String { "corner.\(c.rawValue)" }
        static func cornerApp(_ c: Corner) -> String { "cornerApp.\(c.rawValue)" }
        static func cornerShortcut(_ c: Corner) -> String { "cornerShortcut.\(c.rawValue)" }
        static let tapToPlay = "tapToPlay"
        static let sensitivity = "sensitivity"
        static let edgeWidth = "edgeWidth"
        static let bottomQuarterOnly = "bottomQuarterOnly"
        static let requireModifier = "requireModifier"
        static let freezeCursor = "freezeCursor"
        static let fineControl = "fineControl"
        static let appearance = "appearance"
        static let paused = "paused"
        static let autoUpdate = "autoUpdate"
        static let palmRejection = "palmRejection"
        static let edgeGlow = "edgeGlow"
        static let excludedApps = "excludedApps"
        static let setupDone = "setupDone"
        static let didPromptAccess = "didPromptAccess"
        static let accessNoticeDismissed = "accessNoticeDismissed"
    }

    private init() {
        defaults.register(defaults: [
            Keys.haptics: HapticStrength.medium.rawValue,
            Keys.tapToPlay: false,
            Keys.sensitivity: 1.5,
            Keys.edgeWidth: 0.05,
            Keys.bottomQuarterOnly: false,
            Keys.requireModifier: false,
            Keys.freezeCursor: true,
            Keys.fineControl: true,
            Keys.appearance: Appearance.auto.rawValue,
            Keys.paused: false,
            Keys.autoUpdate: true,
            Keys.palmRejection: true,
            Keys.edgeGlow: true,
            Keys.excludedApps: [String](),
            Keys.setupDone: false,
        ])
        haptics = HapticStrength(rawValue: defaults.string(forKey: Keys.haptics) ?? "") ?? .medium
        tapToPlay = defaults.bool(forKey: Keys.tapToPlay)
        sensitivity = defaults.double(forKey: Keys.sensitivity)
        edgeWidth = defaults.double(forKey: Keys.edgeWidth)
        // Edges and corners, carrying over the older Swap Sides / Media Strip / Quick Mute switches.
        let legacy = (swap: defaults.bool(forKey: Keys.swapSides),
                      strip: defaults.object(forKey: Keys.mediaStrip) as? Bool ?? true,
                      mute: defaults.object(forKey: Keys.quickMute) as? Bool ?? true)
        var edges: [EdgeSide: EdgeFunction] = [:]
        for side in EdgeSide.allCases {
            let fallback = Prefs.defaultEdge(side, swap: legacy.swap, strip: legacy.strip)
            edges[side] = defaults.string(forKey: Keys.edge(side)).flatMap(EdgeFunction.init(rawValue:)) ?? fallback
        }
        self.edges = edges
        var corners: [Corner: CornerFunction] = [:]
        var apps: [Corner: String] = [:]
        var shortcuts: [Corner: String] = [:]
        for c in Corner.allCases {
            let fallback: CornerFunction = legacy.mute ? Prefs.defaultCorner(c) : .off
            corners[c] = defaults.string(forKey: Keys.corner(c)).flatMap(CornerFunction.init(rawValue:)) ?? fallback
            apps[c] = defaults.string(forKey: Keys.cornerApp(c))
            shortcuts[c] = defaults.string(forKey: Keys.cornerShortcut(c))
        }
        self.corners = corners
        self.cornerApps = apps
        self.cornerShortcuts = shortcuts
        bottomQuarterOnly = defaults.bool(forKey: Keys.bottomQuarterOnly)
        requireModifier = defaults.bool(forKey: Keys.requireModifier)
        freezeCursor = defaults.bool(forKey: Keys.freezeCursor)
        fineControl = defaults.bool(forKey: Keys.fineControl)
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .auto
        paused = defaults.bool(forKey: Keys.paused)
        autoUpdate = defaults.bool(forKey: Keys.autoUpdate)
        palmRejection = defaults.bool(forKey: Keys.palmRejection)
        edgeGlow = defaults.bool(forKey: Keys.edgeGlow)
        excludedApps = defaults.stringArray(forKey: Keys.excludedApps) ?? []
        hasCompletedSetup = defaults.bool(forKey: Keys.setupDone)
        didPromptAccess = defaults.bool(forKey: Keys.didPromptAccess)
        accessNoticeDismissed = defaults.bool(forKey: Keys.accessNoticeDismissed)
        refreshOpenAtLogin()
    }

    static func defaultEdge(_ side: EdgeSide, swap: Bool = false, strip: Bool = true) -> EdgeFunction {
        switch side {
        case .left: return swap ? .volume : .brightness
        case .right: return swap ? .brightness : .volume
        case .top: return .off
        case .bottom: return strip ? .songs : .off
        }
    }

    static func defaultCorner(_ c: Corner) -> CornerFunction { c == .topRight ? .mute : .off }

    /// True when edges and corners are exactly as Brim ships.
    var gesturesAreDefault: Bool {
        EdgeSide.allCases.allSatisfy { edge($0) == Prefs.defaultEdge($0) }
            && Corner.allCases.allSatisfy { corner($0) == Prefs.defaultCorner($0) }
            && cornerApps.isEmpty && cornerShortcuts.isEmpty && !tapToPlay
    }

    func edge(_ side: EdgeSide) -> EdgeFunction { edges[side] ?? .off }
    func corner(_ c: Corner) -> CornerFunction { corners[c] ?? .off }

    /// A corner counts as active only when it has something to do.
    func cornerIsActive(_ c: Corner) -> Bool {
        switch corner(c) {
        case .off: return false
        case .openApp: return cornerApps[c] != nil
        case .runShortcut: return cornerShortcuts[c] != nil
        default: return true
        }
    }

    /// Puts only the edges and corners back the way Brim ships.
    func resetGestures() {
        edges = Dictionary(uniqueKeysWithValues: EdgeSide.allCases.map { ($0, Prefs.defaultEdge($0)) })
        corners = Dictionary(uniqueKeysWithValues: Corner.allCases.map { ($0, Prefs.defaultCorner($0)) })
        cornerApps = [:]
        cornerShortcuts = [:]
        tapToPlay = false
    }

    /// Puts every gesture and option back the way Brim ships. Keeps setup, permission and app-list state.
    func restoreDefaults() {
        haptics = .medium
        tapToPlay = false
        sensitivity = 1.5
        edgeWidth = 0.05
        edges = Dictionary(uniqueKeysWithValues: EdgeSide.allCases.map { ($0, Prefs.defaultEdge($0)) })
        corners = Dictionary(uniqueKeysWithValues: Corner.allCases.map { ($0, Prefs.defaultCorner($0)) })
        cornerApps = [:]
        cornerShortcuts = [:]
        bottomQuarterOnly = false
        requireModifier = false
        freezeCursor = true
        fineControl = true
        palmRejection = true
        edgeGlow = true
        paused = false
    }

    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    // MARK: Open at Login

    func refreshOpenAtLogin() {
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Brim: could not change login item: \(error.localizedDescription)")
        }
        refreshOpenAtLogin()
    }
}
