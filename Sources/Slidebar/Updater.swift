import AppKit
import SlidebarCore
import CryptoKit
import Security

/// One entry of the update feed (website/appcast.json).
struct UpdateInfo: Codable, Equatable {
    var version: String
    var build: Int?
    var url: String
    var sha256: String
    var date: String?
    var minimumSystemVersion: String?
    var notes: [String]?
}

/// Checks the feed, downloads the DMG, verifies it, swaps the app in place and relaunches.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var timer: Timer?

    var isConfigured: Bool { AppConfig.updateFeedURL != nil }

    var available: UpdateInfo? {
        if case .available(let info) = phase { return info }
        return nil
    }

    /// Checks shortly after launch and then every 12 hours.
    func startAutomaticChecks() {
        guard isConfigured else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            Task { await self?.check(userInitiated: false) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 12 * 3600, repeats: true) { [weak self] _ in
            Task { await self?.check(userInitiated: false) }
        }
    }

    /// Hides an "up to date" or error notice, or postpones an available update.
    func dismiss() {
        switch phase {
        case .downloading, .installing: return
        default: phase = .idle
        }
    }

    func check(userInitiated: Bool) async {
        guard let feed = AppConfig.updateFeedURL else {
            if userInitiated { phase = .failed("Updates aren't set up for this build.") }
            return
        }
        switch phase {
        case .checking, .downloading, .installing: return
        default: break
        }
        phase = .checking
        do {
            var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("Slidebar/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { throw UpdateError("The update server didn't respond.") }
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)

            let osOK = info.minimumSystemVersion.map { !isVersion($0, newerThan: osVersion()) } ?? true
            if isVersion(info.version, newerThan: AppConfig.version), osOK {
                phase = .available(info)
                if !userInitiated && Prefs.shared.autoUpdate {
                    await install(info)
                }
            } else {
                phase = userInitiated ? .upToDate : .idle
            }
        } catch {
            phase = userInitiated ? .failed(message(for: error)) : .idle
        }
    }

    func install(_ info: UpdateInfo) async {
        phase = .downloading
        do {
            guard let feed = AppConfig.updateFeedURL,
                  let url = URL(string: info.url, relativeTo: feed)?.absoluteURL
            else { throw UpdateError("The update link is broken.") }

            let (downloaded, _) = try await URLSession.shared.download(from: url)
            let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("Slidebar-update-\(UUID().uuidString).dmg")
            try FileManager.default.moveItem(at: downloaded, to: dmg)
            defer { try? FileManager.default.removeItem(at: dmg) }

            let digest = SHA256.hash(data: try Data(contentsOf: dmg)).map { String(format: "%02x", $0) }.joined()
            guard digest == info.sha256.lowercased() else { throw UpdateError("The download was damaged. Try again later.") }

            phase = .installing
            let staged = try await Task.detached { try Self.stage(dmg: dmg) }.value
            try relaunch(replacingWith: staged)
        } catch {
            phase = .failed(message(for: error))
        }
    }

    // MARK: Steps

    /// Mounts the DMG, checks the app's signature, and copies it to a staging folder.
    nonisolated private static func stage(dmg: URL) throws -> URL {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("SlidebarMount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? FileManager.default.removeItem(at: mount)
        }

        let items = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
        guard let newApp = items.first(where: { $0.pathExtension == "app" }) else { throw UpdateError("The update didn't contain the app.") }

        guard isValidlySigned(newApp) else { throw UpdateError("The update's signature isn't valid.") }
        let mine = teamID(of: Bundle.main.bundleURL)
        if let mine, teamID(of: newApp) != mine {
            throw UpdateError("The update was signed by someone else.")
        }

        let stageDir = FileManager.default.temporaryDirectory.appendingPathComponent("SlidebarStage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
        let staged = stageDir.appendingPathComponent("Slidebar.app")
        try run("/usr/bin/ditto", [newApp.path, staged.path])
        return staged
    }

    /// Hands off to a tiny shell script that waits for us to quit, swaps the bundle and reopens it.
    private func relaunch(replacingWith staged: URL) throws {
        let current = Bundle.main.bundleURL
        guard current.pathExtension == "app" else { throw UpdateError("Slidebar isn't running from an app bundle.") }
        guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            throw UpdateError("Slidebar can't write to \(current.deletingLastPathComponent().path).")
        }
        let script = """
        while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$1" && /bin/mv "$2" "$1" && /usr/bin/xattr -dr com.apple.quarantine "$1" 2>/dev/null
        /usr/bin/open "$1"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "brim-update", current.path, staged.path]
        try process.run()
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError("\(URL(fileURLWithPath: tool).lastPathComponent) failed: \(output)") }
        return output
    }

    nonisolated static func isValidlySigned(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
    }

    nonisolated static func teamID(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private func message(for error: Error) -> String {
        if let e = error as? UpdateError { return e.message }
        return error.localizedDescription
    }
}

/// An update failure, with a message written for the user.
struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
