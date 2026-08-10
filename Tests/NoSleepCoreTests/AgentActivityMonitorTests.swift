import XCTest
@testable import NoSleepCore

private final class FakeSampler: ProcessActivitySampling {
    var samples: [ProcessSample] = []
    func sampleProcesses() -> [ProcessSample] { samples }
}

private final class FakePresence: UserPresenceProviding {
    var idleSeconds: TimeInterval = 9_999
    var displayAsleep = true
    func secondsSinceLastUserInput() -> TimeInterval { idleSeconds }
    func isDisplayAsleep() -> Bool { displayAsleep }
}

/// Live bug 2026-08-07: the user woke the Mac at 07:06, worked at the keyboard,
/// and Smart NoSleep still turned NoSleep off at 07:21 — the grace window only
/// looked at agents, so a present human counted as "nothing happening". Worse
/// than a bogus toast: NoSleep silently disarmed itself, so the next lid-close
/// would have slept the Mac mid-run.
final class AgentActivityMonitorTests: XCTestCase {
    private var sampler = FakeSampler()
    private var presence = FakePresence()

    private func makeMonitor() -> AgentActivityMonitor {
        sampler = FakeSampler()
        presence = FakePresence()
        let suite = "com.nosleep.tests.monitor"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AgentActivityMonitor(sampler: sampler,
                                    presence: presence,
                                    store: StateStore(defaults: defaults),
                                    tickInterval: 60)
    }

    private func agent(cpu: TimeInterval) -> [ProcessSample] {
        [ProcessSample(pid: 10, command: "/usr/local/bin/claude", cpuTime: cpu)]
    }

    func testUserAtTheKeyboardNeverTriggersAutoOff() {
        let monitor = makeMonitor()
        var fired = 0
        monitor.onIdle = { fired += 1 }
        monitor.arm(graceMinutes: 1, watchlist: .default)
        presence.idleSeconds = 5
        presence.displayAsleep = false
        for _ in 0..<5 { monitor.tick() }
        XCTAssertEqual(fired, 0)
        XCTAssertEqual(monitor.idleTickCount, 0)
    }

    func testScreenOnNeverTriggersAutoOffEvenWithStaleInput() {
        // Live bug 2026-08-10: reading/watching for 15 min without touching
        // the keyboard fired auto-off with the user right there.
        let monitor = makeMonitor()
        var fired = 0
        monitor.onIdle = { fired += 1 }
        monitor.arm(graceMinutes: 1, watchlist: .default)
        presence.idleSeconds = 1_200
        presence.displayAsleep = false
        for _ in 0..<5 { monitor.tick() }
        XCTAssertEqual(fired, 0)
        XCTAssertEqual(monitor.idleTickCount, 0)
    }

    func testRecentInputHoldsTheCountdownEvenWithTheScreenOff() {
        let monitor = makeMonitor()
        monitor.arm(graceMinutes: 5, watchlist: .default)
        presence.idleSeconds = 3
        presence.displayAsleep = true
        monitor.tick()
        XCTAssertEqual(monitor.idleTickCount, 0)
    }

    func testEmptyHouseRunsTheCountdownToCompletion() {
        let monitor = makeMonitor()
        var fired = 0
        monitor.onIdle = { fired += 1 }
        monitor.arm(graceMinutes: 2, watchlist: .default)
        presence.idleSeconds = 3_600
        monitor.tick()
        XCTAssertEqual(fired, 0, "auto-off must wait out the full grace window")
        monitor.tick()
        XCTAssertEqual(fired, 1)
    }

    func testInputOlderThanTheTickIntervalCountsAsAway() {
        let monitor = makeMonitor()
        monitor.arm(graceMinutes: 5, watchlist: .default)
        presence.idleSeconds = 300
        monitor.tick()
        XCTAssertEqual(monitor.idleTickCount, 1)
    }

    func testUserActivityDoesNotOverwriteLastBusyAgent() {
        let monitor = makeMonitor()
        monitor.arm(graceMinutes: 5, watchlist: .default)
        sampler.samples = agent(cpu: 100)
        monitor.tick()
        sampler.samples = agent(cpu: 200)
        monitor.tick()
        XCTAssertEqual(monitor.lastBusyAgents, ["claude"])
        sampler.samples = []
        presence.idleSeconds = 1
        monitor.tick()
        XCTAssertEqual(monitor.lastBusyAgents, ["claude"],
                       "the notification reports agents, not the user")
    }

    func testRearmingRestartsTheIdleTickCount() {
        let monitor = makeMonitor()
        monitor.arm(graceMinutes: 5, watchlist: .default)
        monitor.tick(); monitor.tick(); monitor.tick()
        XCTAssertEqual(monitor.idleTickCount, 3)
        monitor.arm(graceMinutes: 5, watchlist: .default)
        monitor.tick()
        XCTAssertEqual(monitor.idleTickCount, 1)
    }

    func testWorkingAgentKeepsTheMacAwakeWhileTheUserIsAway() {
        let monitor = makeMonitor()
        var fired = 0
        monitor.onIdle = { fired += 1 }
        // The first tick only baselines CPU counters, so the window has to be
        // wider than one tick.
        monitor.arm(graceMinutes: 2, watchlist: .default)
        sampler.samples = agent(cpu: 100)
        monitor.tick()
        sampler.samples = agent(cpu: 200)
        monitor.tick()
        sampler.samples = agent(cpu: 300)
        monitor.tick()
        XCTAssertEqual(fired, 0)
    }
}
