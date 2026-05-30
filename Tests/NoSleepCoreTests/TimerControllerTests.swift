import XCTest
@testable import NoSleepCore

/// Manual scheduler: records the last scheduled work and fires it on demand.
final class ManualScheduler: TimerScheduling {
    private var work: (() -> Void)?
    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0

    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) {
        scheduleCount += 1
        self.work = work
    }
    func cancel() {
        if work != nil { cancelCount += 1 }
        work = nil
    }
    func fire() {
        let w = work
        work = nil
        w?()
    }
    var hasPending: Bool { work != nil }
}

final class TimerControllerTests: XCTestCase {
    func testFiringCallsExpire() {
        let sched = ManualScheduler()
        var expired = false
        let tc = TimerController(scheduler: sched, onExpire: { expired = true })
        tc.start(seconds: 3600)
        XCTAssertEqual(sched.scheduleCount, 1)
        sched.fire()
        XCTAssertTrue(expired)
    }

    func testStartingNewTimerCancelsOld() {
        let sched = ManualScheduler()
        let tc = TimerController(scheduler: sched, onExpire: {})
        tc.start(seconds: 60)
        tc.start(seconds: 120)
        XCTAssertEqual(sched.cancelCount, 1, "old timer must be cancelled")
        XCTAssertEqual(sched.scheduleCount, 2)
    }

    func testCancelStopsPending() {
        let sched = ManualScheduler()
        var expired = false
        let tc = TimerController(scheduler: sched, onExpire: { expired = true })
        tc.start(seconds: 60)
        tc.cancel()
        XCTAssertFalse(sched.hasPending)
        sched.fire()
        XCTAssertFalse(expired)
    }
}
