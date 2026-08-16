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

    /// Only when nothing has reported the screen state yet — the situation that
    /// kept the Mac awake all night on 2026-08-16.
    func testIdlePastDisplaySleepTimeoutCountsAsDarkWhenNothingElseKnows() {
        XCTAssertTrue(DisplayJudge.isAsleep(DisplaySignals(notifiedAsleep: nil,
                                                           cgReportsAsleep: false,
                                                           hidIdleSeconds: hour + 60,
                                                           displaySleepTimeout: hour)))
        XCTAssertFalse(DisplayJudge.isAsleep(DisplaySignals(hidIdleSeconds: hour - 60,
                                                            displaySleepTimeout: hour)))
    }

    /// Regression guard for the 2026-08-07 and 2026-08-10 complaints: a film or
    /// video call holds the screen lit with no keypresses. Firing there tells
    /// the user their Mac is going to sleep while they are watching it.
    func testLitScreenVetoesTheIdleHeuristic() {
        XCTAssertFalse(DisplayJudge.isAsleep(DisplaySignals(notifiedAsleep: false,
                                                            hidIdleSeconds: 90 * 60,
                                                            displaySleepTimeout: 10 * 60)))
        XCTAssertFalse(DisplayJudge.isAsleep(DisplaySignals(displaysAllOff: false,
                                                            hidIdleSeconds: 86_400,
                                                            displaySleepTimeout: hour)))
    }

    /// Panel power state is direct evidence and outranks a stale notification.
    func testAllPanelsDarkWins() {
        XCTAssertTrue(DisplayJudge.isAsleep(DisplaySignals(notifiedAsleep: false,
                                                           displaysAllOff: true)))
    }

    func testNeverSleepDisplayDisablesTheIdleFallback() {
        XCTAssertFalse(DisplayJudge.isAsleep(DisplaySignals(hidIdleSeconds: 86_400,
                                                            displaySleepTimeout: 0)))
    }
}
