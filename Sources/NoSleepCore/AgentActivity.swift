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
        "copilot",
    ])

    public func matches(_ command: String) -> Bool {
        matchedPattern(command) != nil
    }

    /// The watchlist pattern the command matches, or nil. Used both for
    /// filtering and as the human-readable agent name (versioned binaries
    /// like .../claude/versions/2.1.220 would otherwise surface as "2.1.220").
    public func matchedPattern(_ command: String) -> String? {
        let lower = command.lowercased()
        // GUI chat apps (.app bundles — Claude Desktop, ChatGPT, PWA loaders)
        // never count: their inference runs server-side, so the Mac sleeping
        // loses nothing — while their Electron windows burn enough idle CPU
        // to hold the Mac awake forever. Only local CLI/daemon agents matter.
        if lower.contains(".app/") { return nil }
        return patterns.first { lower.contains($0.lowercased()) }
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

    /// Default threshold 3.0 CPU-seconds per tick: idle agent sessions'
    /// background housekeeping hovers at 0.6–1.7 s/min (live-measured) and
    /// must not count, while real work burns 10s+ per minute.
    public init(watchlist: AgentWatchlist, busyCPUSeconds: TimeInterval = 3.0) {
        self.watchlist = watchlist
        self.busyCPUSeconds = busyCPUSeconds
    }

    /// Records one polling tick. Busy when any watched process burned at
    /// least `busyCPUSeconds` of CPU since the previous tick. A process
    /// seen for the first time only sets a baseline (its cumulative total says
    /// nothing about *recent* activity), and PIDs that vanish are forgotten so
    /// a reused PID re-baselines instead of diffing a stale value.
    public func recordTick(samples: [ProcessSample]) -> ActivityTick {
        var names: Set<String> = []
        var current: [Int32: TimeInterval] = [:]
        for s in samples {
            guard let pattern = watchlist.matchedPattern(s.command) else { continue }
            current[s.pid] = s.cpuTime
            if let prev = lastCPUTime[s.pid], s.cpuTime - prev >= busyCPUSeconds {
                names.insert(pattern)
            }
        }
        lastCPUTime = current
        return ActivityTick(busy: !names.isEmpty, busyAgents: names.sorted())
    }
}

/// Fires `onIdle` once per idle episode: after `graceTicks` consecutive idle
/// ticks. Any busy tick resets the count AND re-arms for the next episode, so
/// Smart NoSleep can doze and re-engage indefinitely. `reset()` re-arms
/// explicitly (fresh grace window).
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
            fired = false
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
