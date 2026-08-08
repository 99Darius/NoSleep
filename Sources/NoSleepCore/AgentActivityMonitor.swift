import Foundation
import os

/// Runs while keep-awake is active in Smart NoSleep mode. Every tick it asks
/// the sampler for process CPU activity and checks the shared-store heartbeat
/// (`nosleep ping`); after a full grace window with neither, fires `onIdle`
/// exactly once so the app can release the sleep block.
/// Concurrency: main thread only (timer is scheduled on the main queue).
public final class AgentActivityMonitor {
    private let sampler: ProcessActivitySampling
    private let presence: UserPresenceProviding
    private let store: StateStore
    private let tickInterval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var tracker: AgentActivityTracker?
    private var detector: IdleDetector?
    private var lastTickDate: Date?
    /// Exposed for tests: how many consecutive ticks saw nothing happening.
    public private(set) var idleTickCount = 0
    // Unified log, subsystem com.nosleep: one line per tick so "why didn't it
    // sleep" is answerable with
    //   log show --info --predicate 'subsystem == "com.nosleep" AND process == "NoSleepApp"'
    // (the process clause matters: coretest drives this same class and its
    // ticks land in the same subsystem)
    private let log = Logger(subsystem: "com.nosleep", category: "smart")

    public var onIdle: (() -> Void)?
    /// For the "went to sleep" notification: which agents were last seen
    /// working, and when. Reset on every start().
    public private(set) var lastBusyAgents: [String] = []
    public private(set) var lastBusyDate: Date?

    public init(sampler: ProcessActivitySampling,
                presence: UserPresenceProviding,
                store: StateStore,
                tickInterval: TimeInterval = 60) {
        self.sampler = sampler
        self.presence = presence
        self.store = store
        self.tickInterval = tickInterval
    }

    public var isRunning: Bool { timer != nil }

    public func start(graceMinutes: Int, watchlist: AgentWatchlist) {
        stop()
        arm(graceMinutes: graceMinutes, watchlist: watchlist)
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + tickInterval, repeating: tickInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Resets the grace window without scheduling a timer. `start()` calls this;
    /// tests drive `tick()` by hand.
    public func arm(graceMinutes: Int, watchlist: AgentWatchlist) {
        let graceTicks = max(1, Int((Double(graceMinutes) * 60 / tickInterval).rounded()))
        tracker = AgentActivityTracker(watchlist: watchlist)
        detector = IdleDetector(graceTicks: graceTicks) { [weak self] in
            self?.onIdle?()
        }
        lastTickDate = Date()
        idleTickCount = 0
        lastBusyAgents = []
        lastBusyDate = nil
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        tracker = nil
        detector = nil
        lastTickDate = nil
    }

    public func tick() {
        guard let tracker, let detector else { return }
        let cpuTick = tracker.recordTick(samples: sampler.sampleProcesses())
        // A `nosleep ping` since the previous tick counts as agent activity.
        let heartbeatBusy: Bool
        if let hb = store.loadHeartbeat(), let last = lastTickDate {
            heartbeatBusy = hb > last
        } else {
            heartbeatBusy = false
        }
        lastTickDate = Date()
        let agentBusy = cpuTick.busy || heartbeatBusy
        // A human at the keyboard holds the countdown: the Mac is in use, so
        // "the agents finished" is not a reason to disarm keep-awake. macOS
        // won't idle-sleep under active input anyway, and disarming here would
        // silently leave the next lid-close unprotected. Input within one tick
        // counts as present; a shut lid can produce none, so this covers
        // clamshell without needing to read the lid switch.
        let userPresent = presence.secondsSinceLastUserInput() <= tickInterval
        if agentBusy {
            var agents = cpuTick.busyAgents
            if heartbeatBusy { agents.append("nosleep ping") }
            // Only agents are recorded here — the "went to sleep" notification
            // reports what was running, not that you touched the trackpad.
            lastBusyAgents = agents
            lastBusyDate = Date()
            log.info("tick: BUSY — \(agents.joined(separator: ", "), privacy: .public)")
        } else if userPresent {
            log.info("tick: user active — countdown held")
        } else {
            idleTickCount += 1
            log.info("tick: idle #\(self.idleTickCount, privacy: .public)")
        }
        if agentBusy || userPresent { idleTickCount = 0 }
        detector.record(busy: agentBusy || userPresent)
    }
}
