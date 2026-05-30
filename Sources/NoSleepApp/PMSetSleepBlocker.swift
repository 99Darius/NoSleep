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
