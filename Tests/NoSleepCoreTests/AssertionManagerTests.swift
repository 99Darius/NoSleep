import XCTest
@testable import NoSleepCore

final class FakeSleepBlocker: SleepBlocking {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    var heldToken: Int? = nil
    /// When true, `begin` fails (returns nil) to simulate a cancelled auth prompt.
    var failBegin = false

    func begin(reason: String) -> Int? {
        beginCount += 1
        if failBegin { return nil }
        heldToken = beginCount
        return beginCount
    }
    func end(token: Int) {
        endCount += 1
        heldToken = nil
    }

    private(set) var niBeginCount = 0
    private(set) var niEndCount = 0
    var failNonInteractive = false

    func beginNonInteractive(reason: String) -> Int? {
        niBeginCount += 1
        if failNonInteractive { return nil }
        heldToken = niBeginCount
        return niBeginCount
    }
    func endNonInteractive(token: Int) -> Bool {
        niEndCount += 1
        if failNonInteractive { return false }
        heldToken = nil
        return true
    }
}

final class AssertionManagerUnattendedTests: XCTestCase {
    func testUnattendedActivateAndDeactivateNeverTouchPromptingCalls() {
        let fake = FakeSleepBlocker()
        let manager = AssertionManager(blocker: fake)
        XCTAssertTrue(manager.activateUnattended())
        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.activateUnattended())   // idempotent
        XCTAssertEqual(fake.niBeginCount, 1)
        XCTAssertTrue(manager.deactivateUnattended())
        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(fake.beginCount, 0)
        XCTAssertEqual(fake.endCount, 0)
    }

    func testUnattendedFailuresKeepStateHonestWithoutPrompting() {
        let fake = FakeSleepBlocker()
        let manager = AssertionManager(blocker: fake)
        fake.failNonInteractive = true
        XCTAssertFalse(manager.activateUnattended())
        XCTAssertFalse(manager.isActive)
        fake.failNonInteractive = false
        manager.activate()
        fake.failNonInteractive = true
        XCTAssertFalse(manager.deactivateUnattended())
        XCTAssertTrue(manager.isActive)   // block is still real — keep saying so
        XCTAssertEqual(fake.endCount, 0)
    }
}

final class AssertionManagerTests: XCTestCase {
    func testActivateHoldsAssertion() {
        let fake = FakeSleepBlocker()
        let m = AssertionManager(blocker: fake)
        m.activate()
        XCTAssertTrue(m.isActive)
        XCTAssertEqual(fake.beginCount, 1)
    }

    func testDoubleActivateDoesNotLeak() {
        let fake = FakeSleepBlocker()
        let m = AssertionManager(blocker: fake)
        m.activate()
        m.activate()
        XCTAssertEqual(fake.beginCount, 1, "second activate must be a no-op")
    }

    func testDeactivateReleases() {
        let fake = FakeSleepBlocker()
        let m = AssertionManager(blocker: fake)
        m.activate()
        m.deactivate()
        XCTAssertFalse(m.isActive)
        XCTAssertEqual(fake.endCount, 1)
    }

    func testDeactivateWhenInactiveIsNoOp() {
        let fake = FakeSleepBlocker()
        let m = AssertionManager(blocker: fake)
        m.deactivate()
        XCTAssertEqual(fake.endCount, 0)
    }

    func testToggleFlips() {
        let fake = FakeSleepBlocker()
        let m = AssertionManager(blocker: fake)
        m.toggle()
        XCTAssertTrue(m.isActive)
        m.toggle()
        XCTAssertFalse(m.isActive)
    }

    func testActivateStaysInactiveWhenBeginFails() {
        let fake = FakeSleepBlocker()
        fake.failBegin = true
        let m = AssertionManager(blocker: fake)
        m.activate()
        XCTAssertFalse(m.isActive, "a failed/cancelled begin must not mark active")
        XCTAssertEqual(fake.beginCount, 1)
    }
}
