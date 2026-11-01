import CryptoKit
import Foundation

/// Offline license keys: a small JSON payload signed with Ed25519.
///
/// Format: `BRIM-<base64url(payload)>.<base64url(signature)>`
/// The app embeds only the public key; keys are issued with `scripts/LicenseTool`.
public struct License: Codable, Equatable {
    /// Who the license belongs to (usually an email).
    public var owner: String
    /// Unix time the key was issued.
    public var issued: Int
    /// Product identifier, so keys for other apps don't validate.
    public var product: String

    public static let productID = "brim"
    public static let prefix = "BRIM-"

    public init(owner: String, issued: Int = Int(Date().timeIntervalSince1970), product: String = License.productID) {
        self.owner = owner
        self.issued = issued
        self.product = product
    }

    public enum Failure: Error, Equatable {
        case malformed, badSignature, wrongProduct, noPublicKey
    }

    /// Checks a pasted key against the public key (raw 32 bytes, base64).
    public static func verify(_ key: String, publicKeyBase64: String) -> Result<License, Failure> {
        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return .failure(.noPublicKey) }

        let cleaned = key.components(separatedBy: .whitespacesAndNewlines).joined()
        guard cleaned.hasPrefix(prefix) else { return .failure(.malformed) }
        let parts = cleaned.dropFirst(prefix.count).split(separator: ".")
        guard parts.count == 2,
              let payload = Data(base64URL: String(parts[0])),
              let signature = Data(base64URL: String(parts[1]))
        else { return .failure(.malformed) }

        guard publicKey.isValidSignature(signature, for: payload) else { return .failure(.badSignature) }
        guard let license = try? JSONDecoder().decode(License.self, from: payload) else { return .failure(.malformed) }
        guard license.product == productID else { return .failure(.wrongProduct) }
        return .success(license)
    }

    /// Creates a key (used by the license tool, never by the app).
    public func issue(with privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(self)
        let signature = try privateKey.signature(for: payload)
        return License.prefix + payload.base64URLEncoded() + "." + signature.base64URLEncoded()
    }
}

/// Trial bookkeeping, kept pure so it can be tested.
public enum Trial {
    public static let length: TimeInterval = 14 * 24 * 60 * 60

    public static func daysLeft(firstLaunch: Date, now: Date = Date(), length: TimeInterval = Trial.length) -> Int {
        let remaining = firstLaunch.addingTimeInterval(length).timeIntervalSince(now)
        return remaining <= 0 ? 0 : Int((remaining / 86_400).rounded(.up))
    }
}

/// Compares dotted version strings ("1.10" > "1.9").
public func isVersion(_ a: String, newerThan b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }
    let y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
        let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
        if l != r { return l > r }
    }
    return false
}

extension Data {
    public init?(base64URL: String) {
        var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }

    public func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
