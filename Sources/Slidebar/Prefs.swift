import AppKit
import SlidebarCore
import Combine
import ServiceManagement

/// How strong the tick under the finger is at each step.
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

/// Light or dark menus, or follow the system.
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

    // Edges and corners
    @Published var edges: [EdgeSide: EdgeFunction] {
        didSet { for (side, f) in edges { defaults.set(f.rawValue, forKey: Keys.edge(side)) } }
    }
    @Published var corners: [Corner: TapFunction] {
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
    /// What a double-tap on each edge (or each third of a split edge) does, alongside its slide or swipe.
    @Published var edgeTaps: [TapSpot: TapFunction] {
        didSet { for spot in TapSpot.allEdges { defaults.set(edgeTaps[spot]?.rawValue, forKey: Keys.edgeTap(spot)) } }
    }
    @Published var edgeTapApps: [TapSpot: String] {
        didSet { for spot in TapSpot.allEdges { defaults.set(edgeTapApps[spot], forKey: Keys.edgeTapApp(spot)) } }
    }
    @Published var edgeTapShortcuts: [TapSpot: String] {
        didSet { for spot in TapSpot.allEdges { defaults.set(edgeTapShortcuts[spot], forKey: Keys.edgeTapShortcut(spot)) } }
    }
    /// Edges whose double-taps are split into three parts.
    @Published var splitEdges: Set<EdgeSide> {
        didSet { for side in EdgeSide.allCases { defaults.set(splitEdges.contains(side), forKey: Keys.splitEdge(side)) } }
    }

    // Feel
    @Published var haptics: HapticStrength { didSet { defaults.set(haptics.rawValue, forKey: Keys.haptics) } }
    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: Keys.sensitivity) } }
    @Published var edgeWidth: Double { didSet { defaults.set(edgeWidth, forKey: Keys.edgeWidth) } }
    @Published var freezeCursor: Bool { didSet { defaults.set(freezeCursor, forKey: Keys.freezeCursor) } }
    @Published var edgeGlow: Bool { didSet { defaults.set(edgeGlow, forKey: Keys.edgeGlow) } }

    // General
    @Published var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            NSApp.appearance = appearance.nsAppearance
        }
    }
    @Published var autoUpdate: Bool { didSet { defaults.set(autoUpdate, forKey: Keys.autoUpdate) } }

    // Advanced
    @Published var bottomQuarterOnly: Bool { didSet { defaults.set(bottomQuarterOnly, forKey: Keys.bottomQuarterOnly) } }
    @Published var palmRejection: Bool { didSet { defaults.set(palmRejection, forKey: Keys.palmRejection) } }
    @Published var requireModifier: Bool { didSet { defaults.set(requireModifier, forKey: Keys.requireModifier) } }
    @Published var fineControl: Bool { didSet { defaults.set(fineControl, forKey: Keys.fineControl) } }

    // State
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: Keys.paused) } }
    @Published var hasCompletedSetup: Bool { didSet { defaults.set(hasCompletedSetup, forKey: Keys.setupDone) } }
    /// The system Accessibility prompt only ever appears once; after that we open System Settings instead.
    @Published var didPromptAccess: Bool { didSet { defaults.set(didPromptAccess, forKey: Keys.didPromptAccess) } }
    /// The user chose to use Slidebar without Accessibility; stop mentioning it in the menu.
    @Published var accessNoticeDismissed: Bool { didSet { defaults.set(accessNoticeDismissed, forKey: Keys.accessNoticeDismissed) } }
    /// The user closed (or acted on) the "star us on GitHub" notice.
    @Published var starNoticeDismissed: Bool { didSet { defaults.set(starNoticeDismissed, forKey: Keys.starNoticeDismissed) } }
    @Published private(set) var openAtLogin: Bool = false

    private enum Keys {
        static let haptics = "haptics"
        static func edge(_ side: EdgeSide) -> String { "edge.\(side.rawValue)" }
        static func corner(_ c: Corner) -> String { "corner.\(c.rawValue)" }
        static func cornerApp(_ c: Corner) -> String { "cornerApp.\(c.rawValue)" }
        static func cornerShortcut(_ c: Corner) -> String { "cornerShortcut.\(c.rawValue)" }
        /// "edgeTap.top" for the whole edge, "edgeTap.top.low" for its left third.
        private static func edgeSuffix(_ spot: TapSpot) -> String {
            guard case .edge(let side, let section) = spot else { return "" }
            return section.map { "\(side.rawValue).\($0.rawValue)" } ?? side.rawValue
        }
        static func edgeTap(_ spot: TapSpot) -> String { "edgeTap.\(edgeSuffix(spot))" }
        static func edgeTapApp(_ spot: TapSpot) -> String { "edgeTapApp.\(edgeSuffix(spot))" }
        static func edgeTapShortcut(_ spot: TapSpot) -> String { "edgeTapShortcut.\(edgeSuffix(spot))" }
        static func splitEdge(_ side: EdgeSide) -> String { "edgeSplit.\(side.rawValue)" }
        static let tapToPlay = "tapToPlay"       // legacy: "double-tap the Songs edge to play or pause"
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
        static let setupDone = "setupDone"
        static let didPromptAccess = "didPromptAccess"
        static let accessNoticeDismissed = "accessNoticeDismissed"
        static let starNoticeDismissed = "starNoticeDismissed"
        // Older switches, read only to carry existing users' settings over to edges and corners.
        static let quickMute = "quickMute"
        static let mediaStrip = "mediaStrip"
        static let swapSides = "swapSides"
    }

    private init() {
        Self.carryOverFromBrim()
        defaults.register(defaults: [
            Keys.haptics: HapticStrength.medium.rawValue,
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
            Keys.setupDone: false,
        ])
        haptics = HapticStrength(rawValue: defaults.string(forKey: Keys.haptics) ?? "") ?? .medium
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
        var corners: [Corner: TapFunction] = [:]
        var apps: [Corner: String] = [:]
        var shortcuts: [Corner: String] = [:]
        for c in Corner.allCases {
            let fallback: TapFunction = legacy.mute ? Prefs.defaultCorner(c) : .off
            corners[c] = defaults.string(forKey: Keys.corner(c)).flatMap(TapFunction.init(rawValue:)) ?? fallback
            apps[c] = defaults.string(forKey: Keys.cornerApp(c))
            shortcuts[c] = defaults.string(forKey: Keys.cornerShortcut(c))
        }
        self.corners = corners
        self.cornerApps = apps
        self.cornerShortcuts = shortcuts
        var taps: [TapSpot: TapFunction] = [:], tapApps: [TapSpot: String] = [:], tapShortcuts: [TapSpot: String] = [:]
        for spot in TapSpot.allEdges {
            taps[spot] = defaults.string(forKey: Keys.edgeTap(spot)).flatMap(TapFunction.init(rawValue:))
            tapApps[spot] = defaults.string(forKey: Keys.edgeTapApp(spot))
            tapShortcuts[spot] = defaults.string(forKey: Keys.edgeTapShortcut(spot))
        }
        // The old "double-tap the Songs edge to play or pause" switch becomes that edge's double-tap.
        for side in EdgeSide.allCases where taps[.edge(side, nil)] == nil && edges[side] == .songs
            && defaults.bool(forKey: Keys.tapToPlay) {
            taps[.edge(side, nil)] = .playPause
        }
        self.edgeTaps = taps
        self.edgeTapApps = tapApps
        self.edgeTapShortcuts = tapShortcuts
        let store = defaults
        self.splitEdges = Set(EdgeSide.allCases.filter { store.bool(forKey: Keys.splitEdge($0)) })
        bottomQuarterOnly = defaults.bool(forKey: Keys.bottomQuarterOnly)
        requireModifier = defaults.bool(forKey: Keys.requireModifier)
        freezeCursor = defaults.bool(forKey: Keys.freezeCursor)
        fineControl = defaults.bool(forKey: Keys.fineControl)
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .auto
        paused = defaults.bool(forKey: Keys.paused)
        autoUpdate = defaults.bool(forKey: Keys.autoUpdate)
        palmRejection = defaults.bool(forKey: Keys.palmRejection)
        edgeGlow = defaults.bool(forKey: Keys.edgeGlow)
        hasCompletedSetup = defaults.bool(forKey: Keys.setupDone)
        didPromptAccess = defaults.bool(forKey: Keys.didPromptAccess)
        accessNoticeDismissed = defaults.bool(forKey: Keys.accessNoticeDismissed)
        starNoticeDismissed = defaults.bool(forKey: Keys.starNoticeDismissed)
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

    static func defaultCorner(_ c: Corner) -> TapFunction { c == .topRight ? .mute : .off }

    func edge(_ side: EdgeSide) -> EdgeFunction { edges[side] ?? .off }
    func corner(_ c: Corner) -> TapFunction { corners[c] ?? .off }

    // MARK: Double-taps, on corners and edges alike

    func tap(_ spot: TapSpot) -> TapFunction {
        switch spot {
        case .corner(let c): return corner(c)
        case .edge: return edgeTaps[spot] ?? .off
        }
    }

    func tapApp(_ spot: TapSpot) -> String? {
        switch spot {
        case .corner(let c): return cornerApps[c]
        case .edge: return edgeTapApps[spot]
        }
    }

    func tapShortcut(_ spot: TapSpot) -> String? {
        switch spot {
        case .corner(let c): return cornerShortcuts[c]
        case .edge: return edgeTapShortcuts[spot]
        }
    }

    /// Sets what a double-tap does; `app` and `shortcut` go with Open an App and Run a Shortcut.
    func setTap(_ spot: TapSpot, _ function: TapFunction, app: String? = nil, shortcut: String? = nil) {
        switch spot {
        case .corner(let c):
            if let app { cornerApps[c] = app }
            if let shortcut { cornerShortcuts[c] = shortcut }
            corners[c] = function
        case .edge:
            if let app { edgeTapApps[spot] = app }
            if let shortcut { edgeTapShortcuts[spot] = shortcut }
            edgeTaps[spot] = function
        }
    }

    /// A double-tap counts only when it has something to do.
    func tapIsActive(_ spot: TapSpot) -> Bool {
        switch tap(spot) {
        case .off: return false
        case .openApp: return tapApp(spot) != nil
        case .runShortcut: return tapShortcut(spot) != nil
        default: return true
        }
    }

    /// The edge's double-tap spots in use now: its three parts when split, otherwise the whole edge.
    func tapSpots(on side: EdgeSide) -> [TapSpot] {
        splitEdges.contains(side) ? EdgeSection.ordered(on: side).map { .edge(side, $0) } : [.edge(side, nil)]
    }

    /// The edge listens for double-taps when any of its current spots has one.
    func edgeHasTaps(_ side: EdgeSide) -> Bool { tapSpots(on: side).contains(where: tapIsActive) }

    /// A short name for small places: the app's or shortcut's own name, or the action's short title.
    func tapShortTitle(_ spot: TapSpot) -> String {
        let f = tap(spot)
        if f == .openApp, let id = tapApp(spot) { return AppNames.name(for: id) }
        if f == .runShortcut, let name = tapShortcut(spot) { return name }
        return f.shortTitle
    }

    /// The double-tap's name as the user would say it ("Open Safari", "Run “Focus”").
    func tapTitle(_ spot: TapSpot) -> String {
        let f = tap(spot)
        if f == .openApp, let id = tapApp(spot) { return "Open \(AppNames.name(for: id))" }
        if f == .runShortcut, let name = tapShortcut(spot) { return "Run \u{201C}\(name)\u{201D}" }
        return f.title
    }

    /// Puts every gesture and option back the way Slidebar ships. Leaves appearance, updates,
    /// Open at Login, setup and notice state alone.
    /// Slidebar used to be called Brim. On first launch, bring over the old app's settings.
    private static func carryOverFromBrim() {
        let defaults = UserDefaults.standard
        guard let id = Bundle.main.bundleIdentifier, id != "app.brim.Brim",
              defaults.object(forKey: Keys.setupDone) == nil,
              let old = defaults.persistentDomain(forName: "app.brim.Brim"), !old.isEmpty else { return }
        for (key, value) in old { defaults.set(value, forKey: key) }
    }

    func restoreDefaults() {
        haptics = .medium
        edgeTaps = [:]
        edgeTapApps = [:]
        edgeTapShortcuts = [:]
        splitEdges = []
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
            NSLog("Slidebar: could not change login item: \(error.localizedDescription)")
        }
        refreshOpenAtLogin()
    }
}
