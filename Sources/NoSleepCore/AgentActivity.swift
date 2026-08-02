import Foundation

/// One process observed at a polling tick.
public struct ProcessSample: Equatable {
    public let pid: Int32
    public let command: String        // executable path or full command line
    public let cpuTime: TimeInterval  // cumulative CPU seconds since process start

    public init(pid: Int32, command: String, cpuTime: TimeInterval) {
        self.pid = pid
        self.command = command
        self.cpuTime = cpuTime
    }
}

/// Seam for the platform process sampler (proc_pid_rusage in the app,
/// a fake in tests).
public protocol ProcessActivitySampling: AnyObject {
    func sampleProcesses() -> [ProcessSample]
}

/// Case-insensitive substring match of agent names against a command line.
public struct AgentWatchlist {
    public let patterns: [String]

    public init(patterns: [String]) {
        self.patterns = patterns
    }

    public static let `default` = AgentWatchlist(patterns: [
        "claude", "codex", "aider", "ollama", "gemini", "cursor-agent",
        "copilot", "ChatGPT",
    ])

    public func matches(_ command: String) -> Bool {
        let lower = command.lowercased()
        return patterns.contains { lower.contains($0.lowercased()) }
    }
}

/// Result of one polling tick: whether any watched agent was busy, and the
/// display names (last path component) of the ones that were.
public struct ActivityTick: Equatable {
    public let busy: Bool
    public let busyAgents: [String]

    public init(busy: Bool, busyAgents: [String]) {
        self.busy = busy
        self.busyAgents = busyAgents
    }
}

/// Turns per-tick process samples into a busy/idle verdict by diffing
/// cumulative CPU time of watched processes between ticks.
/// Concurrency: not thread-safe by design; all calls happen on the main thread.
public final class AgentActivityTracker {
    private let watchlist: AgentWatchlist
    private let busyCPUSeconds: TimeInterval
    private var lastCPUTime: [Int32: TimeInterval] = [:]

    public init(watchlist: AgentWatchlist, busyCPUSeconds: TimeInterval = 1.0) {
        self.watchlist = watchlist
        self.busyCPUSeconds = busyCPUSeconds
    }

    /// Records one polling tick. Busy when any watched process burned at
    /// least `busyCPUSeconds` of CPU since the previous tick. A process
    /// seen for the first time only sets a baseline (its cumulative total says
    /// nothing about *recent* activity), and PIDs that vanish are forgotten so
    /// a reused PID re-baselines instead of diffing a stale value.
    public func recordTick(samples: [ProcessSample]) -> ActivityTick {
        let watched = samples.filter { watchlist.matches($0.command) }
        var names: Set<String> = []
        var current: [Int32: TimeInterval] = [:]
        for s in watched {
            current[s.pid] = s.cpuTime
            if let prev = lastCPUTime[s.pid], s.cpuTime - prev >= busyCPUSeconds {
                names.insert((s.command as NSString).lastPathComponent)
            }
        }
        lastCPUTime = current
        return ActivityTick(busy: !names.isEmpty, busyAgents: names.sorted())
    }
}

/// Fires `onIdle` once after `graceTicks` consecutive idle ticks.
/// Any busy tick resets the count; `reset()` re-arms after firing.
/// Concurrency: not thread-safe by design; all calls happen on the main thread.
public final class IdleDetector {
    private let graceTicks: Int
    private let onIdle: () -> Void
    private var idleTicks = 0
    private var fired = false

    public init(graceTicks: Int, onIdle: @escaping () -> Void) {
        self.graceTicks = graceTicks
        self.onIdle = onIdle
    }

    public func record(busy: Bool) {
        if busy {
            idleTicks = 0
            return
        }
        idleTicks += 1
        if idleTicks >= graceTicks && !fired {
            fired = true
            onIdle()
        }
    }

    public func reset() {
        idleTicks = 0
        fired = false
    }
}
