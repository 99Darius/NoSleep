import Foundation
import AppKit
import NoSleepCore

let bundleID = "com.nosleep"
let store = StateStore.shared()

func runningAgentPID() -> Int? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first.map { Int($0.processIdentifier) }
}

func agentRunning() -> Bool {
    runningAgentPID() != nil
}

/// `open -b` the agent (fire-and-forget launch; readiness is awaited separately).
func openAgent() {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    proc.arguments = ["-b", bundleID]
    try? proc.run()
    proc.waitUntilExit()
}

/// Ensure the agent is running AND its DistributedNotificationCenter observer is
/// ready before we post. Process existence is NOT sufficient: the observer is
/// registered partway through `applicationDidFinishLaunching`, and a notification
/// posted before that is silently dropped (DNC does not queue). The agent calls
/// `store.save(..., pid:)` at the END of launch (after `addObserver`), so the
/// shared store holding the *currently running* pid is our readiness signal.
/// Returns true once ready. Launches the agent first if `launchIfNeeded`.
func ensureAgentReady(launchIfNeeded: Bool) -> Bool {
    if !agentRunning() {
        guard launchIfNeeded else { return false }
        openAgent()
    }
    for _ in 0..<50 {   // up to ~5s
        if let pid = runningAgentPID(), store.loadPID() == pid { return true }
        usleep(100_000)
    }
    return false
}

/// Poll the shared store until `predicate` holds, up to ~1.5s (100ms steps).
/// Graceful fallback: returns after the timeout regardless.
func waitForState(_ predicate: (NoSleepState) -> Bool) {
    for _ in 0..<15 {
        if predicate(store.load()) { return }
        usleep(100_000)
    }
}

func post(_ cmd: Command) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.nosleep.cmd"),
        object: nil, userInfo: cmd.userInfo,
        deliverImmediately: true)
}

func printState() {
    // Treat stale state as inactive when agent is dead.
    let running = agentRunning()
    let state = running ? store.load() : .inactive
    if state.isActive {
        if let exp = state.expiresAt {
            print("active (\(formatDuration(seconds: max(0, exp.timeIntervalSinceNow))) left)")
        } else {
            print("active")
        }
    } else {
        print("inactive")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = Command.parse(args) else {
    FileHandle.standardError.write(Data("usage: nosleep [on|off|toggle|status|timer <15m|1h|2h|90s>]\n".utf8))
    exit(2)
}

switch cmd {
case .status:
    printState()
case .off:
    // Nothing to do if the agent isn't running (no assertion is held).
    if agentRunning(), ensureAgentReady(launchIfNeeded: false) {
        post(.off)
        waitForState { !$0.isActive }
    }
    printState()
case .on:
    if ensureAgentReady(launchIfNeeded: true) {
        post(.on)
        waitForState { $0.isActive }
    }
    printState()
case .toggle:
    if ensureAgentReady(launchIfNeeded: true) {
        let wasActive = store.load().isActive
        post(.toggle)
        waitForState { $0.isActive != wasActive }
    }
    printState()
case .timer:
    if ensureAgentReady(launchIfNeeded: true) {
        post(cmd)
        waitForState { $0.isActive }
    }
    printState()
}
