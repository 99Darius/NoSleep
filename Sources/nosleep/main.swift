import Foundation
import AppKit
import NoSleepCore

let bundleID = "com.nosleep"
let store = StateStore.shared()

func agentRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
}

func launchAgent() {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    proc.arguments = ["-b", bundleID]
    try? proc.run()
    proc.waitUntilExit()
    // Wait until the agent's DistributedNotificationCenter observer is registered.
    // The agent calls store.save(..., pid:) at the END of applicationDidFinishLaunching
    // (after addObserver), so a matching fresh pid in the shared store means the
    // observer exists and any subsequent post will be delivered.
    for _ in 0..<30 {
        if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier,
           store.loadPID() == Int(pid) {
            break
        }
        usleep(100_000)
    }
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
        object: nil, userInfo: cmd.userInfo as? [String: Any],
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
    if agentRunning() {
        post(.off)
        waitForState { !$0.isActive }
    }
    printState()
case .on:
    if !agentRunning() { launchAgent() }
    post(.on)
    waitForState { $0.isActive }
    printState()
case .toggle:
    if !agentRunning() { launchAgent() }
    let wasActive = store.load().isActive
    post(.toggle)
    waitForState { $0.isActive != wasActive }
    printState()
case .timer:
    if !agentRunning() { launchAgent() }
    post(cmd)
    waitForState { $0.isActive }
    printState()
}
