import XCTest
@testable import NoSleepCore

/// Live miss 2026-08-16: the screen was off from 00:03 to 04:48, but
/// CGDisplayIsAsleep reported "awake" the whole time, so the grace countdown
/// never advanced and the Mac stayed awake all night on a closed-lid setup.
final class DisplayJudgeTests: XCTestCase {
    private let hour: TimeInterval = 3600

    func testSleepNotificationMeansDark() {
        XCTAssertTrue(DisplayJudge.isAsleep(DisplaySignals(notifiedAsleep: true)))
        // Even with input a moment ago — the lid can shut mid-keystroke.
        XCTAssertTrue(DisplayJudge.isAsleep(DisplaySignals(notifiedAsleep: true,
                                                           hidIdleSeconds: 0,
                                                           displaySleepTimeout: hour)))
    }

    func testLitScreenWithRecentInputIsNotDark() {
        XCTAssertFalse(DisplayJudge.isAsleep(DisplaySignals(notifiedAsleep: false,
                                                            hidIdleSeconds: 30,
                                                            displaySleepTimeout: hour)))
    }

    func testCoreGraphicsSignalIsStillBelievedWhenItReportsSleep() {
        XCTAssertTrue(DisplayJudge.isAsleep(DisplaySignals(cgReportsAsleep: true)))
    }

    func testIdlePastDisplaySleepTimeoutCountsAsDark() {
        XCTAssertTrue(DisplayJudge.isAsleep(DisplaySignals(notifiedAsleep: false,
                                                           cgReportsAsleep: false,
                                                           hidIdleSeconds: hour + 60,
                                                           displaySleepTimeout: hour)))
        XCTAssertFalse(DisplayJudge.isAsleep(DisplaySignals(hidIdleSeconds: hour - 60,
                                                            displaySleepTimeout: hour)))
    }

    func testNeverSleepDisplayDisablesTheIdleFallback() {
        XCTAssertFalse(DisplayJudge.isAsleep(DisplaySignals(hidIdleSeconds: 86_400,
                                                            displaySleepTimeout: 0)))
    }
}
