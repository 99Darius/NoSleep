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
    // brief wait for heartbeat
    for _ in 0..<20 where !agentRunning() { usleep(100_000) }
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
    if agentRunning() { post(.off); usleep(200_000) }
    printState()
default:
    if !agentRunning() { launchAgent() }
    post(cmd)
    usleep(200_000)   // let agent update shared state
    printState()
}
