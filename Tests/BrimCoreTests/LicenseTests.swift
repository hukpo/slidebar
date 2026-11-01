import CryptoKit
import XCTest
@testable import BrimCore

final class LicenseTests: XCTestCase {
    let privateKey = Curve25519.Signing.PrivateKey()
    var publicKey: String { privateKey.publicKey.rawRepresentation.base64EncodedString() }

    func testIssuedKeyVerifies() throws {
        let key = try License(owner: "ada@example.com", issued: 1_800_000_000).issue(with: privateKey)
        XCTAssertTrue(key.hasPrefix("BRIM-"))
        XCTAssertEqual(try License.verify(key, publicKeyBase64: publicKey).get().owner, "ada@example.com")
    }

    func testWhitespaceAndLineBreaksAreIgnored() throws {
        let key = try License(owner: "a@b.c").issue(with: privateKey)
        let pasted = "  " + key.prefix(20) + "\n" + key.dropFirst(20) + " \n"
        XCTAssertNoThrow(try License.verify(String(pasted), publicKeyBase64: publicKey).get())
    }

    func testTamperedKeyFails() throws {
        let key = try License(owner: "a@b.c").issue(with: privateKey)
        var chars = Array(key)
        let i = 10
        chars[i] = chars[i] == "A" ? "B" : "A"
        let result = License.verify(String(chars), publicKeyBase64: publicKey)
        if case .success = result { XCTFail("tampered key accepted") }
    }

    func testKeyFromAnotherSignerFails() throws {
        let key = try License(owner: "a@b.c").issue(with: Curve25519.Signing.PrivateKey())
        XCTAssertEqual(License.verify(key, publicKeyBase64: publicKey), .failure(.badSignature))
    }

    func testWrongProductFails() throws {
        let key = try License(owner: "a@b.c", product: "other").issue(with: privateKey)
        XCTAssertEqual(License.verify(key, publicKeyBase64: publicKey), .failure(.wrongProduct))
    }

    func testGarbage() {
        XCTAssertEqual(License.verify("hello", publicKeyBase64: publicKey), .failure(.malformed))
        XCTAssertEqual(License.verify("BRIM-abc", publicKeyBase64: publicKey), .failure(.malformed))
        XCTAssertEqual(License.verify("BRIM-a.b", publicKeyBase64: ""), .failure(.noPublicKey))
    }

    func testTrialDays() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Trial.daysLeft(firstLaunch: start, now: start), 14)
        XCTAssertEqual(Trial.daysLeft(firstLaunch: start, now: start.addingTimeInterval(13.5 * 86_400)), 1)
        XCTAssertEqual(Trial.daysLeft(firstLaunch: start, now: start.addingTimeInterval(14 * 86_400)), 0)
        XCTAssertEqual(Trial.daysLeft(firstLaunch: start, now: start.addingTimeInterval(40 * 86_400)), 0)
    }

    func testVersionCompare() {
        XCTAssertTrue(isVersion("1.10", newerThan: "1.9"))
        XCTAssertTrue(isVersion("1.0.1", newerThan: "1.0"))
        XCTAssertFalse(isVersion("1.0", newerThan: "1.0.0"))
        XCTAssertFalse(isVersion("0.9", newerThan: "1.0"))
    }
}
