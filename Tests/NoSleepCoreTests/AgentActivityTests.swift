import XCTest
@testable import NoSleepCore

final class AgentWatchlistTests: XCTestCase {
    func testMatchesExecutableNameCaseInsensitively() {
        let list = AgentWatchlist(patterns: ["claude"])
        XCTAssertTrue(list.matches("/usr/local/bin/Claude"))
        XCTAssertTrue(list.matches("claude"))
    }

    func testMatchesSubstringInFullCommandLine() {
        let list = AgentWatchlist.default
        XCTAssertTrue(list.matches("/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=utility"))
        XCTAssertTrue(list.matches("/opt/homebrew/bin/ollama serve"))
    }

    func testDoesNotMatchUnrelatedProcesses() {
        let list = AgentWatchlist.default
        XCTAssertFalse(list.matches("/bin/bash"))
        XCTAssertFalse(list.matches("/usr/sbin/mDNSResponder"))
    }

    func testDefaultListCoversKnownAgents() {
        let list = AgentWatchlist.default
        for cmd in ["claude", "codex", "aider", "ollama", "gemini", "cursor-agent"] {
            XCTAssertTrue(list.matches(cmd), "\(cmd) should be watched by default")
        }
    }
}

final class AgentActivityTrackerTests: XCTestCase {
    private func sample(_ pid: Int32, _ command: String, cpu: TimeInterval) -> ProcessSample {
        ProcessSample(pid: pid, command: command, cpuTime: cpu)
    }

    func testFirstSightingIsNotBusy() {
        let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]))
        // No baseline yet — cumulative CPU alone must not count as activity.
        XCTAssertFalse(tracker.recordTick(samples: [sample(10, "claude", cpu: 500)]).busy)
    }

    func testCPUDeltaAtOrAboveThresholdIsBusyAndNamesAgent() {
        let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]),
                                           busyCPUSeconds: 1.0)
        _ = tracker.recordTick(samples: [sample(10, "claude", cpu: 500)])
        let tick = tracker.recordTick(samples: [sample(10, "claude", cpu: 501.5)])
        XCTAssertTrue(tick.busy)
        XCTAssertEqual(tick.busyAgents, ["claude"])
    }

    func testBusyAgentsAreDisplayNamesSorted() {
        let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude", "ollama"]),
                                           busyCPUSeconds: 1.0)
        _ = tracker.recordTick(samples: [sample(10, "/usr/local/bin/claude", cpu: 500),
                                         sample(11, "/opt/homebrew/bin/ollama", cpu: 40)])
        let tick = tracker.recordTick(samples: [sample(10, "/usr/local/bin/claude", cpu: 502),
                                                sample(11, "/opt/homebrew/bin/ollama", cpu: 45)])
        XCTAssertEqual(tick.busyAgents, ["claude", "ollama"])
    }

    func testCPUDeltaBelowThresholdIsIdle() {
        let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]),
                                           busyCPUSeconds: 1.0)
        _ = tracker.recordTick(samples: [sample(10, "claude", cpu: 500)])
        let tick = tracker.recordTick(samples: [sample(10, "claude", cpu: 500.2)])
        XCTAssertFalse(tick.busy)
        XCTAssertTrue(tick.busyAgents.isEmpty)
    }

    func testUnwatchedProcessDeltaDoesNotCount() {
        let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]),
                                           busyCPUSeconds: 1.0)
        _ = tracker.recordTick(samples: [sample(20, "/usr/bin/ffmpeg", cpu: 100)])
        XCTAssertFalse(tracker.recordTick(samples: [sample(20, "/usr/bin/ffmpeg", cpu: 200)]).busy)
    }

    func testDisappearedProcessIsForgotten() {
        let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]),
                                           busyCPUSeconds: 1.0)
        _ = tracker.recordTick(samples: [sample(10, "claude", cpu: 500)])
        _ = tracker.recordTick(samples: [])   // process exited
        // PID reused by a fresh process: must re-baseline, not diff against 500.
        XCTAssertFalse(tracker.recordTick(samples: [sample(10, "claude", cpu: 900)]).busy)
    }
}

final class IdleDetectorTests: XCTestCase {
    func testFiresAfterConsecutiveIdleTicks() {
        var fired = 0
        let d = IdleDetector(graceTicks: 3, onIdle: { fired += 1 })
        d.record(busy: false)
        d.record(busy: false)
        XCTAssertEqual(fired, 0)
        d.record(busy: false)
        XCTAssertEqual(fired, 1)
    }

    func testBusyTickResetsCount() {
        var fired = 0
        let d = IdleDetector(graceTicks: 3, onIdle: { fired += 1 })
        d.record(busy: false)
        d.record(busy: false)
        d.record(busy: true)
        d.record(busy: false)
        d.record(busy: false)
        XCTAssertEqual(fired, 0)
        d.record(busy: false)
        XCTAssertEqual(fired, 1)
    }

    func testFiresOnlyOnceUntilReset() {
        var fired = 0
        let d = IdleDetector(graceTicks: 1, onIdle: { fired += 1 })
        d.record(busy: false)
        d.record(busy: false)
        XCTAssertEqual(fired, 1)
        d.reset()
        d.record(busy: false)
        XCTAssertEqual(fired, 2)
    }
}
