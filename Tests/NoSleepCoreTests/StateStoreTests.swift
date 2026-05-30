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

final class StateStoreTests: XCTestCase {
    private func makeStore() -> (StateStore, UserDefaults) {
        let suite = "com.nosleep.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (StateStore(defaults: defaults), defaults)
    }

    func testDefaultsToInactive() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.load(), .inactive)
    }

    func testRoundTrip() {
        let (store, _) = makeStore()
        let when = Date(timeIntervalSince1970: 5000)
        let state = NoSleepState(isActive: true, expiresAt: when)
        store.save(state, pid: 4321)
        XCTAssertEqual(store.load(), state)
        XCTAssertEqual(store.loadPID(), 4321)
    }
}
