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

// MARK: - Doze/re-engage (2026-08-12): auto-off must not disarm the mode
//
// Live complaint: "it keeps switching the mode back to yes-sleep". Every fire
// flipped the toggle off for good; the user had to re-enable by hand each
// morning. Smart NoSleep now stays armed: the block releases when idle and
// re-engages when agents work again — so the detector must be able to fire
// once per idle episode, and the monitor must report when agents resume.

do {
    // After a fire, a busy tick re-arms the detector for the next episode.
    var fired = 0
    let d = IdleDetector(graceTicks: 2, onIdle: { fired += 1 })
    d.record(busy: false); d.record(busy: false)
    check(fired == 1, "detector fires at the end of the first idle episode")
    d.record(busy: false)
    check(fired == 1, "detector stays quiet while the same episode continues")
    d.record(busy: true)
    d.record(busy: false); d.record(busy: false)
    check(fired == 2, "busy tick re-arms the detector for the next idle episode")
}
do {
    // Monitor surfaces agent resumption so the app can re-engage the block.
    let sampler = FakeSampler(), presence = FakePresence()
    let monitor = makeMonitor(sampler, presence)
    var resumed: [[String]] = []
    monitor.onBusy = { resumed.append($0) }
    monitor.arm(graceMinutes: 5, watchlist: .default)
    sampler.samples = [sample(10, "/usr/local/bin/claude", cpu: 100)]
    monitor.tick()
    check(resumed.isEmpty, "baseline tick does not report busy agents")
    sampler.samples = [sample(10, "/usr/local/bin/claude", cpu: 200)]
    monitor.tick()
    check(resumed == [["claude"]], "busy tick reports the working agents via onBusy")
}
do {
    // Dozing state persists for the CLI/menu; old persisted JSON (no key)
    // must still decode.
    let dozing = NoSleepState(isActive: false, expiresAt: nil, dozing: true)
    let data = try! JSONEncoder().encode(dozing)
    let back = try! JSONDecoder().decode(NoSleepState.self, from: data)
    check(back.dozing == true, "dozing round-trips through Codable")
    let legacy = try! JSONDecoder().decode(NoSleepState.self,
                                           from: Data(#"{"isActive":true}"#.utf8))
    check(legacy.isActive && legacy.dozing != true, "legacy state JSON decodes without dozing")
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

// MARK: - AgentActivityMonitor: the countdown only runs when nobody is home
//
// Live bug 2026-08-07: the user woke the Mac at 07:06, worked at the keyboard,
// and Smart NoSleep still turned NoSleep off at 07:21 — the grace window only
// looked at agents, so a present human counted as "nothing happening". Worse
// than a bogus toast: NoSleep silently disarmed itself, so the next lid-close
// would have slept the Mac mid-run.

final class FakeSampler: ProcessActivitySampling {
    var samples: [ProcessSample] = []
    func sampleProcesses() -> [ProcessSample] { samples }
}

final class FakePresence: UserPresenceProviding {
    var idleSeconds: TimeInterval = 9_999
    var displayAsleep = true
    func secondsSinceLastUserInput() -> TimeInterval { idleSeconds }
    func isDisplayAsleep() -> Bool { displayAsleep }
}

func makeMonitor(_ sampler: FakeSampler,
                 _ presence: FakePresence) -> AgentActivityMonitor {
    let suite = "com.nosleep.coretest.monitor"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return AgentActivityMonitor(sampler: sampler,
                                presence: presence,
                                store: StateStore(defaults: defaults),
                                tickInterval: 60)
}

do {
    // Human at the keyboard: no agent is running, but the Mac is in use, so the
    // countdown must not advance — let alone fire.
    let sampler = FakeSampler(), presence = FakePresence()
    let monitor = makeMonitor(sampler, presence)
    var fired = 0
    monitor.onIdle = { fired += 1 }
    monitor.arm(graceMinutes: 1, watchlist: .default)
    presence.idleSeconds = 5      // typed 5 seconds ago
    presence.displayAsleep = false
    for _ in 0..<5 { monitor.tick() }
    check(fired == 0, "user at the keyboard never triggers auto-off")
    check(monitor.idleTickCount == 0, "user activity holds the idle counter at zero")
}
do {
    // Live bug 2026-08-10: reading/watching for 15 min without touching the
    // keyboard fired auto-off with the user right there. The screen being on
    // means someone is looking at it — input recency alone must not decide.
    let sampler = FakeSampler(), presence = FakePresence()
    let monitor = makeMonitor(sampler, presence)
    var fired = 0
    monitor.onIdle = { fired += 1 }
    monitor.arm(graceMinutes: 1, watchlist: .default)
    presence.idleSeconds = 1_200   // 20 min since last input (watching a video)
    presence.displayAsleep = false // but the screen is on
    for _ in 0..<5 { monitor.tick() }
    check(fired == 0, "screen on never triggers auto-off, even with stale input")
    check(monitor.idleTickCount == 0, "screen on holds the idle counter at zero")
}
do {
    // Screen off but input seconds ago: a transition blip — hold.
    let sampler = FakeSampler(), presence = FakePresence()
    let monitor = makeMonitor(sampler, presence)
    monitor.arm(graceMinutes: 5, watchlist: .default)
    presence.idleSeconds = 3
    presence.displayAsleep = true
    monitor.tick()
    check(monitor.idleTickCount == 0, "recent input holds the countdown even with the screen off")
}
do {
    // Nobody home (lid shut, or walked away): countdown runs and fires.
    let sampler = FakeSampler(), presence = FakePresence()
    let monitor = makeMonitor(sampler, presence)
    var fired = 0
    monitor.onIdle = { fired += 1 }
    monitor.arm(graceMinutes: 2, watchlist: .default)
    presence.idleSeconds = 3_600
    monitor.tick()
    check(fired == 0, "auto-off waits out the full grace window")
    monitor.tick()
    check(fired == 1, "no agent and no human for the grace window triggers auto-off")
}
do {
    // Input older than the gap between ticks means the human left.
    let sampler = FakeSampler(), presence = FakePresence()
    let monitor = makeMonitor(sampler, presence)
    monitor.arm(graceMinutes: 5, watchlist: .default)
    presence.idleSeconds = 300
    monitor.tick()
    check(monitor.idleTickCount == 1, "input older than the tick interval counts as away")
}
do {
    // The "went to sleep" toast names the last agent. A human tapping the
    // trackpad must not overwrite that with themselves.
    let sampler = FakeSampler(), presence = FakePresence()
    let monitor = makeMonitor(sampler, presence)
    monitor.arm(graceMinutes: 5, watchlist: .default)
    sampler.samples = [sample(10, "/usr/local/bin/claude", cpu: 100)]
    monitor.tick()
    sampler.samples = [sample(10, "/usr/local/bin/claude", cpu: 200)]
    monitor.tick()
    check(monitor.lastBusyAgents == ["claude"], "monitor records the busy agent")
    sampler.samples = []
    presence.idleSeconds = 1
    monitor.tick()
    check(monitor.lastBusyAgents == ["claude"], "user activity does not overwrite the last busy agent")
}
do {
    // Re-arming (mode/grace change) starts a fresh window: the log numbering
    // restarts at #1 instead of continuing from the previous run.
    let sampler = FakeSampler(), presence = FakePresence()
    let monitor = makeMonitor(sampler, presence)
    monitor.arm(graceMinutes: 5, watchlist: .default)
    monitor.tick(); monitor.tick(); monitor.tick()
    check(monitor.idleTickCount == 3, "idle ticks accumulate within a window")
    monitor.arm(graceMinutes: 5, watchlist: .default)
    monitor.tick()
    check(monitor.idleTickCount == 1, "re-arming restarts the idle tick count")
}
do {
    // A busy agent still wins even when the user is away. (The first tick only
    // baselines CPU counters, so the window has to be wider than one tick.)
    let sampler = FakeSampler(), presence = FakePresence()
    let monitor = makeMonitor(sampler, presence)
    var fired = 0
    monitor.onIdle = { fired += 1 }
    monitor.arm(graceMinutes: 2, watchlist: .default)
    sampler.samples = [sample(10, "/usr/local/bin/claude", cpu: 100)]
    monitor.tick()
    sampler.samples = [sample(10, "/usr/local/bin/claude", cpu: 200)]
    monitor.tick()
    sampler.samples = [sample(10, "/usr/local/bin/claude", cpu: 300)]
    monitor.tick()
    check(fired == 0, "a working agent keeps the Mac awake while the user is away")
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

// MARK: - Heartbeat naming (user-facing text must never say "nosleep ping")

func makeMonitorWithStore(_ sampler: FakeSampler,
                          _ presence: FakePresence) -> (AgentActivityMonitor, StateStore) {
    let suite = "com.nosleep.coretest.hb.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = StateStore(defaults: defaults)
    let monitor = AgentActivityMonitor(sampler: sampler,
                                       presence: presence,
                                       store: store,
                                       tickInterval: 60)
    return (monitor, store)
}

do {
    let suite = "com.nosleep.coretest.hbname"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = StateStore(defaults: defaults)
    store.saveHeartbeat(Date(), name: "claude")
    check(store.loadHeartbeatName() == "claude", "heartbeat name round-trips through store")
    store.saveHeartbeat(Date())
    check(store.loadHeartbeatName() == nil, "nameless ping clears the stored heartbeat name")
    defaults.removePersistentDomain(forName: suite)
}

do {
    // Heartbeat-only activity reports the pinging agent's real name.
    let sampler = FakeSampler(), presence = FakePresence()
    let (monitor, store) = makeMonitorWithStore(sampler, presence)
    var resumed: [[String]] = []
    monitor.onBusy = { resumed.append($0) }
    monitor.arm(graceMinutes: 2, watchlist: .default)
    monitor.tick()                                   // baseline
    store.saveHeartbeat(Date(), name: "claude")
    monitor.tick()
    check(resumed == [["claude"]], "heartbeat busy reports the pinging agent's name")
    check(monitor.lastBusyAgents == ["claude"],
          "lastBusyAgents records the ping name, never 'nosleep ping'")
}

do {
    // Heartbeat + CPU activity for the same agent must not duplicate the name.
    let sampler = FakeSampler(), presence = FakePresence()
    let (monitor, store) = makeMonitorWithStore(sampler, presence)
    var resumed: [[String]] = []
    monitor.onBusy = { resumed.append($0) }
    monitor.arm(graceMinutes: 2, watchlist: .default)
    sampler.samples = [sample(10, "/usr/local/bin/claude", cpu: 100)]
    monitor.tick()                                   // baseline
    store.saveHeartbeat(Date(), name: "claude")
    sampler.samples = [sample(10, "/usr/local/bin/claude", cpu: 300)]
    monitor.tick()
    check(resumed == [["claude"]], "CPU + ping for the same agent reports it once")
}

do {
    // A nameless ping still counts as activity — with no agent names to report.
    let sampler = FakeSampler(), presence = FakePresence()
    let (monitor, store) = makeMonitorWithStore(sampler, presence)
    var fired = 0
    var resumed: [[String]] = []
    monitor.onIdle = { fired += 1 }
    monitor.onBusy = { resumed.append($0) }
    monitor.arm(graceMinutes: 2, watchlist: .default)
    monitor.tick()                                   // baseline
    store.saveHeartbeat(Date())
    monitor.tick()
    check(fired == 0 && resumed == [[]],
          "nameless ping is busy with an empty agent list — no 'nosleep ping' label")
}

// MARK: - SmartRecap message

do {
    // 1_700_000_000 = 2023-11-14 22:13:20 UTC
    let sleptAt = Date(timeIntervalSince1970: 1_700_000_000)
    let utc = TimeZone(identifier: "UTC")!
    let withAgents = SmartRecap.message(sleptAt: sleptAt, graceMinutes: 5,
                                        agents: ["claude"], timeZone: utc)
    check(withAgents == "Smart NoSleep let your Mac sleep at 22:13 after 5 min of quiet. Last running: claude.",
          "recap message names the time, grace and last agents")
    let noAgents = SmartRecap.message(sleptAt: sleptAt, graceMinutes: 15,
                                      agents: [], timeZone: utc)
    check(noAgents == "Smart NoSleep let your Mac sleep at 22:13 after 15 min of quiet.",
          "recap message omits agents when none were recorded")
}

// MARK: - StateStore pending recap

do {
    let suite = "com.nosleep.coretest.recap"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = StateStore(defaults: defaults)
    check(store.loadPendingRecap() == nil, "no pending recap by default")
    let recap = PendingRecap(sleptAt: Date(timeIntervalSince1970: 1_700_000_000),
                             agents: ["claude", "nosleep ping"])
    store.savePendingRecap(recap)
    check(store.loadPendingRecap() == recap, "pending recap round-trips through store")
    store.clearPendingRecap()
    check(store.loadPendingRecap() == nil, "clearPendingRecap removes the pending recap")
    defaults.removePersistentDomain(forName: suite)
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
