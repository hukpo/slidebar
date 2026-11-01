import AppKit
import BrimCore

/// Values baked into Info.plist by scripts/build.sh. Any of them may be empty.
enum AppConfig {
    private static func string(_ key: String) -> String? {
        // A defaults override makes local testing easy: `defaults write app.brim.Brim BrimUpdateFeedURL <url>`
        let value = UserDefaults.standard.string(forKey: key)
            ?? (Bundle.main.object(forInfoDictionaryKey: key) as? String)
        guard let value, !value.isEmpty, !value.hasPrefix("__") else { return nil }
        return value
    }

    static var licensePublicKey: String? { string("BrimLicensePublicKey") }
    static var updateFeedURL: URL? { string("BrimUpdateFeedURL").flatMap(URL.init(string:)) }
    static var checkoutURL: URL? { string("BrimCheckoutURL").flatMap(URL.init(string:)) }
    static var websiteURL: URL? { string("BrimWebsiteURL").flatMap(URL.init(string:)) }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}

/// Trial and license state. Builds without a public key are free and unlimited.
final class Licensing: ObservableObject {
    static let shared = Licensing()

    enum State: Equatable {
        case free
        case trial(daysLeft: Int)
        case licensed(owner: String)
        case expired
    }

    @Published private(set) var state: State = .free

    private let defaults = UserDefaults.standard
    private let keyDefaultsKey = "licenseKey"
    private let firstLaunchKey = "firstLaunchDate"

    var allowsGestures: Bool { state != .expired }
    var isLicensed: Bool { if case .licensed = state { return true } else { return false } }
    var canBuy: Bool {
        switch state {
        case .trial, .expired: return true
        case .free, .licensed: return false
        }
    }

    private init() {
        if defaults.object(forKey: firstLaunchKey) == nil {
            defaults.set(Date(), forKey: firstLaunchKey)
        }
        evaluate()
    }

    func evaluate() {
        let newState: State
        if let publicKey = AppConfig.licensePublicKey {
            if let key = defaults.string(forKey: keyDefaultsKey),
               case .success(let license) = License.verify(key, publicKeyBase64: publicKey) {
                newState = .licensed(owner: license.owner)
            } else {
                let first = defaults.object(forKey: firstLaunchKey) as? Date ?? Date()
                let days = Trial.daysLeft(firstLaunch: first)
                newState = days > 0 ? .trial(daysLeft: days) : .expired
            }
        } else {
            newState = .free
        }
        if newState != state { state = newState }
    }

    /// Returns an error message, or nil on success.
    func activate(_ key: String) -> String? {
        guard let publicKey = AppConfig.licensePublicKey else { return "This build of Brim doesn't need a license." }
        switch License.verify(key, publicKeyBase64: publicKey) {
        case .success:
            defaults.set(key.components(separatedBy: .whitespacesAndNewlines).joined(), forKey: keyDefaultsKey)
            evaluate()
            return nil
        case .failure(.badSignature):
            return "That key isn't valid. Check that you copied all of it."
        case .failure(.wrongProduct):
            return "That key is for a different app."
        case .failure:
            return "That doesn't look like a Brim key. Keys start with BRIM-."
        }
    }

    func deactivate() {
        defaults.removeObject(forKey: keyDefaultsKey)
        evaluate()
    }

    func openCheckout() {
        if let url = AppConfig.checkoutURL ?? AppConfig.websiteURL?.appendingPathComponent("#get") {
            NSWorkspace.shared.open(url)
        }
    }

    func openLostKey() {
        if let url = AppConfig.websiteURL?.appendingPathComponent("lost-key.html") {
            NSWorkspace.shared.open(url)
        }
    }
}
