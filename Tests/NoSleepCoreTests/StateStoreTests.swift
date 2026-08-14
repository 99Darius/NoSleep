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

    func testDozingRoundTripsAndLegacyJSONDecodes() {
        let dozing = NoSleepState(isActive: false, expiresAt: nil, dozing: true)
        let back = try! JSONDecoder().decode(NoSleepState.self,
                                             from: try! JSONEncoder().encode(dozing))
        XCTAssertEqual(back.dozing, true)
        let legacy = try! JSONDecoder().decode(NoSleepState.self,
                                               from: Data(#"{"isActive":true}"#.utf8))
        XCTAssertTrue(legacy.isActive)
        XCTAssertNil(legacy.dozing)
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

    func testHeartbeatDefaultsToNil() {
        let (store, _) = makeStore()
        XCTAssertNil(store.loadHeartbeat())
    }

    func testHeartbeatRoundTrip() {
        let (store, _) = makeStore()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        store.saveHeartbeat(stamp)
        XCTAssertEqual(store.loadHeartbeat(), stamp)
    }

    func testHeartbeatNameRoundTripsAndNamelessPingClearsIt() {
        let (store, _) = makeStore()
        store.saveHeartbeat(Date(), name: "claude")
        XCTAssertEqual(store.loadHeartbeatName(), "claude")
        store.saveHeartbeat(Date())
        XCTAssertNil(store.loadHeartbeatName())
    }

    func testPendingRecapDefaultsToNil() {
        let (store, _) = makeStore()
        XCTAssertNil(store.loadPendingRecap())
    }

    func testPendingRecapRoundTripAndClear() {
        let (store, _) = makeStore()
        let recap = PendingRecap(sleptAt: Date(timeIntervalSince1970: 1_700_000_000),
                                 agents: ["claude", "nosleep ping"])
        store.savePendingRecap(recap)
        XCTAssertEqual(store.loadPendingRecap(), recap)
        store.clearPendingRecap()
        XCTAssertNil(store.loadPendingRecap())
    }
}

final class SmartRecapTests: XCTestCase {
    private let sleptAt = Date(timeIntervalSince1970: 1_700_000_000)  // 22:13 UTC
    private let utc = TimeZone(identifier: "UTC")!

    func testMessageNamesTimeGraceAndAgents() {
        XCTAssertEqual(
            SmartRecap.message(sleptAt: sleptAt, graceMinutes: 5,
                               agents: ["claude"], timeZone: utc),
            "Smart NoSleep let your Mac sleep at 22:13 after 5 min of quiet. Last running: claude.")
    }

    func testMessageOmitsAgentsWhenNoneRecorded() {
        XCTAssertEqual(
            SmartRecap.message(sleptAt: sleptAt, graceMinutes: 15,
                               agents: [], timeZone: utc),
            "Smart NoSleep let your Mac sleep at 22:13 after 15 min of quiet.")
    }
}
