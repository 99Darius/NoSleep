import Foundation
import NoSleepCore

/// Keeps the Mac awake even with the lid closed by setting `pmset disablesleep 1`.
/// This is the only mechanism that survives clamshell (lid-close) sleep; a normal
/// IOKit idle assertion does not. Changing `disablesleep` requires root, so each
/// begin/end runs `pmset` through a macOS administrator authorization prompt.
final class PMSetSleepBlocker: SleepBlocking {
    private var heldTokens: Set<Int> = []
    private var nextKey = 1

    func begin(reason: String) -> Int? {
        guard setDisableSleep(true) else { return nil }   // user cancelled / failed
        let key = nextKey
        nextKey += 1
        heldTokens.insert(key)
        return key
    }

    func end(token: Int) {
        guard heldTokens.contains(token) else { return }
        _ = setDisableSleep(false)
        heldTokens.remove(token)
    }

    /// Reads whether system sleep is currently disabled. No root required.
    /// `pmset -g` lists a `disablesleep` line only when it is set.
    static func systemSleepDisabled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-g"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return false }
        for line in out.split(separator: "\n") where line.contains("disablesleep") {
            return line.split(separator: " ").last == "1"
        }
        return false
    }

    /// Force-restore normal sleep (admin prompt). Recovers a leftover
    /// `disablesleep 1` from a previous force-quit. Returns true on success.
    @discardableResult
    func forceRestoreSleep() -> Bool {
        let ok = setDisableSleep(false)
        if ok { heldTokens.removeAll() }
        return ok
    }

    /// Returns true if `disablesleep` was set successfully.
    @discardableResult
    private func setDisableSleep(_ on: Bool) -> Bool {
        let value = on ? "1" : "0"
        // do shell script ... with administrator privileges shows the standard
        // macOS auth dialog and caches the authorization briefly.
        let source = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }
}
