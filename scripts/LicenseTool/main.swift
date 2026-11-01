// Brim license tool.
//   scripts/license.sh keygen                 → creates .secrets/license-private.key and license-public.key
//   scripts/license.sh issue <owner>          → prints a license key for <owner> (usually their email)
//   scripts/license.sh verify <key>           → checks a key against the public key
import CryptoKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
let secrets = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BRIM_SECRETS"] ?? ".secrets")
let privateURL = secrets.appendingPathComponent("license-private.key")
let publicURL = secrets.appendingPathComponent("license-public.key")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func read(_ url: URL) -> String {
    guard let s = try? String(contentsOf: url, encoding: .utf8) else { fail("Missing \(url.path). Run `keygen` first.") }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

switch args.first {
case "keygen":
    if FileManager.default.fileExists(atPath: privateURL.path) {
        fail("\(privateURL.path) already exists. Delete it first if you really want new keys (old licenses will stop working).")
    }
    try FileManager.default.createDirectory(at: secrets, withIntermediateDirectories: true)
    let key = Curve25519.Signing.PrivateKey()
    try key.rawRepresentation.base64EncodedString().write(to: privateURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateURL.path)
    try key.publicKey.rawRepresentation.base64EncodedString().write(to: publicURL, atomically: true, encoding: .utf8)
    print("Wrote \(privateURL.path) (keep secret, never commit)")
    print("Wrote \(publicURL.path) (embedded in the app by scripts/build.sh)")

case "issue":
    guard args.count >= 2 else { fail("usage: issue <owner>") }
    guard let raw = Data(base64Encoded: read(privateURL)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("Bad private key.") }
    print(try License(owner: args[1]).issue(with: key))

case "verify":
    guard args.count >= 2 else { fail("usage: verify <key>") }
    switch License.verify(args[1], publicKeyBase64: read(publicURL)) {
    case .success(let license):
        print("Valid. Owner: \(license.owner), issued \(Date(timeIntervalSince1970: TimeInterval(license.issued)))")
    case .failure(let error):
        fail("Invalid: \(error)")
    }

default:
    fail("usage: license.sh keygen | issue <owner> | verify <key>")
}
