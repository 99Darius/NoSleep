import Foundation
import NoSleepCore
import os

/// Runs while keep-awake is active in Smart NoSleep mode. Every tick it asks
/// the sampler for process CPU activity and checks the shared-store heartbeat
/// (`nosleep ping`); after a full grace window with neither, fires `onIdle`
/// exactly once so the app can release the sleep block.
/// Concurrency: main thread only (timer is scheduled on the main queue).
final class AgentActivityMonitor {
    private let sampler: ProcessActivitySampling
    private let store: StateStore
    private let tickInterval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var tracker: AgentActivityTracker?
    private var detector: IdleDetector?
    private var lastTickDate: Date?
    private var idleTickCount = 0
    // Unified log, subsystem com.nosleep: one line per tick so "why didn't it
    // sleep" is answerable with
    //   log show --last 30m --predicate 'subsystem == "com.nosleep"'
    private let log = Logger(subsystem: "com.nosleep", category: "smart")

    var onIdle: (() -> Void)?
    /// For the "went to sleep" notification: which agents were last seen
    /// working, and when. Reset on every start().
    private(set) var lastBusyAgents: [String] = []
    private(set) var lastBusyDate: Date?

    init(sampler: ProcessActivitySampling,
         store: StateStore,
         tickInterval: TimeInterval = 60) {
        self.sampler = sampler
        self.store = store
        self.tickInterval = tickInterval
    }

    var isRunning: Bool { timer != nil }

    func start(graceMinutes: Int, watchlist: AgentWatchlist) {
        stop()
        let graceTicks = max(1, Int((Double(graceMinutes) * 60 / tickInterval).rounded()))
        tracker = AgentActivityTracker(watchlist: watchlist)
        detector = IdleDetector(graceTicks: graceTicks) { [weak self] in
            self?.onIdle?()
        }
        lastTickDate = Date()
        lastBusyAgents = []
        lastBusyDate = nil
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + tickInterval, repeating: tickInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        tracker = nil
        detector = nil
        lastTickDate = nil
    }

    private func tick() {
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
        let busy = cpuTick.busy || heartbeatBusy
        if busy {
            var agents = cpuTick.busyAgents
            if heartbeatBusy { agents.append("nosleep ping") }
            lastBusyAgents = agents
            lastBusyDate = Date()
            idleTickCount = 0
            log.info("tick: BUSY — \(agents.joined(separator: ", "), privacy: .public)")
        } else {
            idleTickCount += 1
            log.info("tick: idle #\(self.idleTickCount, privacy: .public)")
        }
        detector.record(busy: busy)
    }
}
