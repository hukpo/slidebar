import AppKit
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
    @Published var quickMute: Bool { didSet { defaults.set(quickMute, forKey: Keys.quickMute) } }
    @Published var mediaStrip: Bool { didSet { defaults.set(mediaStrip, forKey: Keys.mediaStrip) } }
    @Published var tapToPlay: Bool { didSet { defaults.set(tapToPlay, forKey: Keys.tapToPlay) } }
    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: Keys.sensitivity) } }
    @Published var edgeWidth: Double { didSet { defaults.set(edgeWidth, forKey: Keys.edgeWidth) } }

    // Settings page
    @Published var swapSides: Bool { didSet { defaults.set(swapSides, forKey: Keys.swapSides) } }
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
    @Published private(set) var openAtLogin: Bool = false

    private enum Keys {
        static let haptics = "haptics"
        static let quickMute = "quickMute"
        static let mediaStrip = "mediaStrip"
        static let tapToPlay = "tapToPlay"
        static let sensitivity = "sensitivity"
        static let edgeWidth = "edgeWidth"
        static let swapSides = "swapSides"
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
    }

    private init() {
        defaults.register(defaults: [
            Keys.haptics: HapticStrength.medium.rawValue,
            Keys.quickMute: true,
            Keys.mediaStrip: true,
            Keys.tapToPlay: false,
            Keys.sensitivity: 1.5,
            Keys.edgeWidth: 0.05,
            Keys.swapSides: false,
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
        quickMute = defaults.bool(forKey: Keys.quickMute)
        mediaStrip = defaults.bool(forKey: Keys.mediaStrip)
        tapToPlay = defaults.bool(forKey: Keys.tapToPlay)
        sensitivity = defaults.double(forKey: Keys.sensitivity)
        edgeWidth = defaults.double(forKey: Keys.edgeWidth)
        swapSides = defaults.bool(forKey: Keys.swapSides)
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
        refreshOpenAtLogin()
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
