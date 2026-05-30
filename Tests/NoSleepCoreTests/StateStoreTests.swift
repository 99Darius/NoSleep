import XCTest
@testable import NoSleepCore

final class NoSleepStateTests: XCTestCase {
    func testInactiveByDefault() {
        let s = NoSleepState.inactive
        XCTAssertFalse(s.isActive)
        XCTAssertNil(s.expiresAt)
    }

    func testActiveWithExpiry() {
        let when = Date(timeIntervalSince1970: 1000)
        let s = NoSleepState(isActive: true, expiresAt: when)
        XCTAssertTrue(s.isActive)
        XCTAssertEqual(s.expiresAt, when)
    }
}
