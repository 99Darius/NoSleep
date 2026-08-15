import Foundation
import NoSleepCore

/// Keeps the Mac awake even with the lid closed by setting `pmset disablesleep 1`.
/// This is the only mechanism that survives clamshell (lid-close) sleep; a normal
/// IOKit idle assertion does not. Changing `disablesleep` requires root. To
/// avoid an admin prompt on every toggle, the first call installs a passwordless
/// `sudoers` drop-in (single prompt, ever); afterwards each begin/end runs
/// `sudo -n pmset …` with no prompt at all.
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

    /// Unattended begin/end (Smart auto-off / re-engage, possibly at 3 AM with
    /// nobody present): `sudo -n` only — on failure return failure, NEVER fall
    /// through to the AppleScript admin prompts. A modal password prompt
    /// looping once per monitor tick is worse than staying in the current state.
    func beginNonInteractive(reason: String) -> Int? {
        guard runSudoNoPrompt("1") else { return nil }
        let key = nextKey
        nextKey += 1
        heldTokens.insert(key)
        return key
    }

    func endNonInteractive(token: Int) -> Bool {
        guard heldTokens.contains(token) else { return true }
        guard runSudoNoPrompt("0") else { return false }
        heldTokens.remove(token)
        return true
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
    ///
    /// First tries a passwordless `sudo -n` (no prompt). The very first time —
    /// when that fails because the rule isn't installed yet — it installs the
    /// `sudoers` drop-in via a single admin prompt, then retries silently. Every
    /// later begin/end runs with no prompt at all.
    @discardableResult
    private func setDisableSleep(_ on: Bool) -> Bool {
        let value = on ? "1" : "0"

        // Fast path: passwordless rule already installed → no prompt.
        if runSudoNoPrompt(value) { return true }

        // First time only: install the rule (one prompt), then retry silently.
        if installSudoersRule() && runSudoNoPrompt(value) { return true }

        // Fallback (install declined/failed): legacy direct admin prompt.
        return runPmsetViaAdmin(value)
    }

    /// Runs `sudo -n /usr/bin/pmset -a disablesleep <value>`.
    /// `-n` never prompts; it fails fast when the passwordless rule is absent.
    private func runSudoNoPrompt(_ value: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", value]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Installs `/etc/sudoers.d/nosleep` granting the admin group passwordless
    /// rights to *only* `pmset -a disablesleep 0|1`. Single admin prompt.
    /// The rule is validated with `visudo -cf` before being moved into place.
    private func installSudoersRule() -> Bool {
        let rule = """
        Cmnd_Alias NOSLEEP_PMSET = /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
        %admin ALL=(root) NOPASSWD: NOSLEEP_PMSET
        """
        // base64 keeps the multi-line rule out of shell/AppleScript quoting hell;
        // its alphabet (A–Z a–z 0–9 + / =) is safe to pass unquoted.
        let b64 = Data(rule.utf8).base64EncodedString()
        let tmp = "/tmp/com.nosleep.sudoers"
        let dst = "/etc/sudoers.d/nosleep"
        let shell = "echo \(b64) | /usr/bin/base64 -D -o \(tmp)"
            + " && /usr/sbin/visudo -cf \(tmp)"
            + " && /usr/bin/install -m 0440 -o root -g wheel \(tmp) \(dst)"
            + " && /bin/rm -f \(tmp)"
        let source = "do shell script \"\(shell)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    /// Legacy fallback: prompt for admin and run pmset directly.
    private func runPmsetViaAdmin(_ value: String) -> Bool {
        let source = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }
}
