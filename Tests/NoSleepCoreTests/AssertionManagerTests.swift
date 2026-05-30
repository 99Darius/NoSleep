import XCTest
@testable import NoSleepCore

final class FakeSleepBlocker: SleepBlocking {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    var heldToken: Int? = nil

    func begin(reason: String) -> Int {
        beginCount += 1
        heldToken = beginCount
        return beginCount
    }
    func end(token: Int) {
        endCount += 1
        heldToken = nil
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
}
