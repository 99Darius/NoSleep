// Minimal test harness for machines without XCTest (Command Line Tools only).
// Mirrors Tests/NoSleepCoreTests. Run with: swift run coretest
import Foundation
import NoSleepCore

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if cond {
        print("PASS \(name)")
    } else {
        failures += 1
        print("FAIL \(name)")
    }
}

// MARK: - AgentWatchlist

do {
    let list = AgentWatchlist(patterns: ["claude"])
    check(list.matches("/usr/local/bin/Claude"), "watchlist matches executable name case-insensitively")
    check(list.matches("claude"), "watchlist matches bare name")
}
do {
    let list = AgentWatchlist.default
    check(list.matches("/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=utility"),
          "default watchlist matches Claude Helper command line")
    check(list.matches("/opt/homebrew/bin/ollama serve"), "default watchlist matches ollama")
    check(!list.matches("/bin/bash"), "default watchlist ignores bash")
    check(!list.matches("/usr/sbin/mDNSResponder"), "default watchlist ignores mDNSResponder")
    for cmd in ["claude", "codex", "aider", "ollama", "gemini", "cursor-agent"] {
        check(list.matches(cmd), "default watchlist covers \(cmd)")
    }
}

// MARK: - AgentActivityTracker

func sample(_ pid: Int32, _ command: String, cpu: TimeInterval) -> ProcessSample {
    ProcessSample(pid: pid, command: command, cpuTime: cpu)
}

do {
    let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]))
    check(!tracker.recordTick(samples: [sample(10, "claude", cpu: 500)]),
          "first sighting is not busy (no baseline)")
}
do {
    let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]), busyCPUSeconds: 1.0)
    _ = tracker.recordTick(samples: [sample(10, "claude", cpu: 500)])
    check(tracker.recordTick(samples: [sample(10, "claude", cpu: 501.5)]),
          "cpu delta >= threshold is busy")
}
do {
    let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]), busyCPUSeconds: 1.0)
    _ = tracker.recordTick(samples: [sample(10, "claude", cpu: 500)])
    check(!tracker.recordTick(samples: [sample(10, "claude", cpu: 500.2)]),
          "cpu delta below threshold is idle")
}
do {
    let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]), busyCPUSeconds: 1.0)
    _ = tracker.recordTick(samples: [sample(20, "/usr/bin/ffmpeg", cpu: 100)])
    check(!tracker.recordTick(samples: [sample(20, "/usr/bin/ffmpeg", cpu: 200)]),
          "unwatched process delta does not count")
}
do {
    let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]), busyCPUSeconds: 1.0)
    _ = tracker.recordTick(samples: [sample(10, "claude", cpu: 500)])
    _ = tracker.recordTick(samples: [])
    check(!tracker.recordTick(samples: [sample(10, "claude", cpu: 900)]),
          "disappeared pid re-baselines instead of diffing stale value")
}

// MARK: - IdleDetector

do {
    var fired = 0
    let d = IdleDetector(graceTicks: 3, onIdle: { fired += 1 })
    d.record(busy: false)
    d.record(busy: false)
    check(fired == 0, "idle detector holds before grace window")
    d.record(busy: false)
    check(fired == 1, "idle detector fires after consecutive idle ticks")
}
do {
    var fired = 0
    let d = IdleDetector(graceTicks: 3, onIdle: { fired += 1 })
    d.record(busy: false)
    d.record(busy: false)
    d.record(busy: true)
    d.record(busy: false)
    d.record(busy: false)
    check(fired == 0, "busy tick resets idle count")
    d.record(busy: false)
    check(fired == 1, "idle detector fires after reset + grace idle ticks")
}
do {
    var fired = 0
    let d = IdleDetector(graceTicks: 1, onIdle: { fired += 1 })
    d.record(busy: false)
    d.record(busy: false)
    check(fired == 1, "idle detector fires only once")
    d.reset()
    d.record(busy: false)
    check(fired == 2, "reset re-arms idle detector")
}

// MARK: - Command.ping

do {
    check(Command.parse(["ping"]) == .ping, "parse ping verb")
    check(Command(userInfo: Command.ping.userInfo) == .ping, "ping round-trips through userInfo")
}

// MARK: - StateStore heartbeat

do {
    let suite = "com.nosleep.coretest"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = StateStore(defaults: defaults)
    check(store.loadHeartbeat() == nil, "no heartbeat by default")
    let stamp = Date(timeIntervalSince1970: 1_700_000_000)
    store.saveHeartbeat(stamp)
    check(store.loadHeartbeat() == stamp, "heartbeat round-trips through store")
    defaults.removePersistentDomain(forName: suite)
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
