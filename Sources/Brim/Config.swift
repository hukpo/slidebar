import AppKit

/// Values baked into Info.plist by scripts/build.sh. Any of them may be empty.
enum AppConfig {
    private static func string(_ key: String) -> String? {
        // A defaults override makes local testing easy: `defaults write app.brim.Brim BrimUpdateFeedURL <url>`
        let value = UserDefaults.standard.string(forKey: key)
            ?? (Bundle.main.object(forInfoDictionaryKey: key) as? String)
        guard let value, !value.isEmpty, !value.hasPrefix("__") else { return nil }
        return value
    }

    static var updateFeedURL: URL? { string("BrimUpdateFeedURL").flatMap(URL.init(string:)) }
    /// Where the source code lives. Forks can point this elsewhere with SOURCE_URL in scripts/build.sh.
    static var sourceURL: URL? { URL(string: string("BrimSourceURL") ?? defaultSourceURL) }
    static let defaultSourceURL = "https://github.com/hukpo/brim"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
