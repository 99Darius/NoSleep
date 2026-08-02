import XCTest
@testable import NoSleepCore

final class CommandTests: XCTestCase {
    func testParseSimple() {
        XCTAssertEqual(Command.parse(["on"]), .on)
        XCTAssertEqual(Command.parse(["off"]), .off)
        XCTAssertEqual(Command.parse(["toggle"]), .toggle)
        XCTAssertEqual(Command.parse(["status"]), .status)
        XCTAssertEqual(Command.parse(["ping"]), .ping)
    }

    func testParseTimerDurations() {
        XCTAssertEqual(Command.parse(["timer", "15m"]), .timer(900))
        XCTAssertEqual(Command.parse(["timer", "1h"]), .timer(3600))
        XCTAssertEqual(Command.parse(["timer", "2h"]), .timer(7200))
        XCTAssertEqual(Command.parse(["timer", "90s"]), .timer(90))
    }

    func testParseInvalid() {
        XCTAssertNil(Command.parse([]))
        XCTAssertNil(Command.parse(["bogus"]))
        XCTAssertNil(Command.parse(["timer"]))
        XCTAssertNil(Command.parse(["timer", "abc"]))
    }

    func testParseDurationRejectsNegative() {
        XCTAssertNil(parseDuration("-5m"))
        XCTAssertNil(Command.parse(["timer", "-5m"]))
        // Fractional durations remain allowed.
        XCTAssertEqual(parseDuration("1.5h"), 5400)
    }

    func testTimerUserInfoDecodesNSNumber() {
        // Mirrors the real DistributedNotificationCenter decode path, where
        // numeric payload values arrive as NSNumber.
        let info: [AnyHashable: Any] = ["action": "timer",
                                        "seconds": NSNumber(value: 3600.0)]
        XCTAssertEqual(Command(userInfo: info), .timer(3600))
    }

    func testRoundTripViaUserInfo() {
        for c in [Command.on, .off, .toggle, .status, .timer(3600), .ping] {
            let info = c.userInfo
            XCTAssertEqual(Command(userInfo: info), c)
        }
    }

    func testFormatDuration() {
        XCTAssertEqual(formatDuration(seconds: 0), "0s")
        XCTAssertEqual(formatDuration(seconds: 60), "1m")
        XCTAssertEqual(formatDuration(seconds: 90), "1m30s")
        XCTAssertEqual(formatDuration(seconds: 3600), "1h")
        XCTAssertEqual(formatDuration(seconds: 3660), "1h1m")
        XCTAssertEqual(formatDuration(seconds: 3720), "1h2m")
    }
}
