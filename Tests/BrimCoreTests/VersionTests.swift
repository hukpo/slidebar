import XCTest
@testable import BrimCore

final class VersionTests: XCTestCase {
    func testVersionCompare() {
        XCTAssertTrue(isVersion("1.10", newerThan: "1.9"))
        XCTAssertTrue(isVersion("1.0.1", newerThan: "1.0"))
        XCTAssertFalse(isVersion("1.0", newerThan: "1.0.0"))
        XCTAssertFalse(isVersion("0.9", newerThan: "1.0"))
    }
}
