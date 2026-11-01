import AppKit
import CBrimPrivate

/// Small "ticks" under the finger while sliding.
enum Haptics {
    private static var actuatorWorks = true

    static func tick(_ strength: HapticStrength) {
        guard strength != .off else { return }

        // The Force Touch actuator gives real control over strength.
        if actuatorWorks {
            let id: Int32
            switch strength {
            case .light: id = 3
            case .medium: id = 4
            case .strong: id = 6
            case .off: return
            }
            if BrimHapticActuate(id) { return }
            actuatorWorks = false
        }

        // Public fallback.
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch strength {
        case .light: pattern = .alignment
        case .medium: pattern = .levelChange
        case .strong: pattern = .generic
        case .off: return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
