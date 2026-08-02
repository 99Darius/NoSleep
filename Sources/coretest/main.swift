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
    // GUI chat apps (.app bundles) must NOT count: their inference runs
    // server-side, and an open Electron window burns enough CPU to hold the
    // Mac awake forever (live-test lesson, round 3).
    check(!list.matches("/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"),
          "default watchlist ignores Claude Desktop helpers (.app bundle)")
    check(!list.matches("/Applications/Claude.app/Contents/MacOS/Claude"),
          "default watchlist ignores Claude Desktop main binary (.app bundle)")
    check(!list.matches("/Users/x/Applications/Chrome Apps.localized/Claude.app/Contents/MacOS/app_mode_loader"),
          "default watchlist ignores Claude PWA loader (.app bundle)")
    check(list.matches("/opt/homebrew/bin/ollama serve"), "default watchlist matches ollama")
    check(list.matches("/Users/x/.claude/local/claude"), "default watchlist matches claude CLI")
    check(list.matches("/Users/x/.local/share/claude/versions/2.1.220"),
          "default watchlist matches claude versioned binary")
    check(list.matchedPattern("/Users/x/.local/share/claude/versions/2.1.220") == "claude",
          "matchedPattern returns readable agent name for versioned binary")
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
    check(!tracker.recordTick(samples: [sample(10, "claude", cpu: 500)]).busy,
          "first sighting is not busy (no baseline)")
}
do {
    let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]), busyCPUSeconds: 1.0)
    _ = tracker.recordTick(samples: [sample(10, "claude", cpu: 500)])
    let tick = tracker.recordTick(samples: [sample(10, "claude", cpu: 501.5)])
    check(tick.busy, "cpu delta >= threshold is busy")
    check(tick.busyAgents == ["claude"], "busy tick names the active agent")
}
do {
    let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude", "ollama"]), busyCPUSeconds: 1.0)
    _ = tracker.recordTick(samples: [sample(10, "/usr/local/bin/claude", cpu: 500),
                                     sample(11, "/opt/homebrew/bin/ollama", cpu: 40)])
    let tick = tracker.recordTick(samples: [sample(10, "/usr/local/bin/claude", cpu: 502),
                                            sample(11, "/opt/homebrew/bin/ollama", cpu: 45)])
    check(tick.busyAgents.sorted() == ["claude", "ollama"],
          "busy agents report display names, deduped and sorted")
}
do {
    // Versioned binary paths (Claude Code installs as .../claude/versions/2.1.220)
    // must surface the agent name, not the version number.
    let tracker = AgentActivityTracker(watchlist: .default, busyCPUSeconds: 1.0)
    _ = tracker.recordTick(samples: [sample(10, "/Users/x/.local/share/claude/versions/2.1.220", cpu: 100)])
    let tick = tracker.recordTick(samples: [sample(10, "/Users/x/.local/share/claude/versions/2.1.220", cpu: 130)])
    check(tick.busyAgents == ["claude"], "busy agent named by matched pattern, not basename")
}
do {
    // Default threshold must ignore idle-session housekeeping (~1 CPU-sec/min)
    // but catch real work. Live-test lesson: idle claude sessions hover at
    // 0.6–1.7 s/min and held the Mac awake at the old 1.0 threshold.
    let tracker = AgentActivityTracker(watchlist: .default)   // default threshold
    _ = tracker.recordTick(samples: [sample(10, "claude", cpu: 100)])
    check(!tracker.recordTick(samples: [sample(10, "claude", cpu: 101.7)]).busy,
          "default threshold ignores idle-session housekeeping (1.7s/min)")
    check(tracker.recordTick(samples: [sample(10, "claude", cpu: 112)]).busy,
          "default threshold catches real work (10s/min)")
}
do {
    let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]), busyCPUSeconds: 1.0)
    _ = tracker.recordTick(samples: [sample(10, "claude", cpu: 500)])
    let tick = tracker.recordTick(samples: [sample(10, "claude", cpu: 500.2)])
    check(!tick.busy, "cpu delta below threshold is idle")
    check(tick.busyAgents.isEmpty, "idle tick names no agents")
}
do {
    let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]), busyCPUSeconds: 1.0)
    _ = tracker.recordTick(samples: [sample(20, "/usr/bin/ffmpeg", cpu: 100)])
    check(!tracker.recordTick(samples: [sample(20, "/usr/bin/ffmpeg", cpu: 200)]).busy,
          "unwatched process delta does not count")
}
do {
    let tracker = AgentActivityTracker(watchlist: AgentWatchlist(patterns: ["claude"]), busyCPUSeconds: 1.0)
    _ = tracker.recordTick(samples: [sample(10, "claude", cpu: 500)])
    _ = tracker.recordTick(samples: [])
    check(!tracker.recordTick(samples: [sample(10, "claude", cpu: 900)]).busy,
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

// MARK: - AgentProcessSampler (real libproc — regression for the
// proc_listallpids return-value bug: it returns a PID COUNT, not bytes;
// treating it as bytes sampled only 1/4 of processes and Smart NoSleep
// never saw the agents)

do {
    let samples = AgentProcessSampler().sampleProcesses()
    check(samples.count > 200, "sampler sees the whole process table (got \(samples.count))")
    let me = ProcessInfo.processInfo.processIdentifier
    let mine = samples.first { $0.pid == me }
    check(mine != nil, "sampler includes this very process")
    check((mine?.cpuTime ?? 0) > 0.01, "sampler reports plausible cpu time for this process")
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
