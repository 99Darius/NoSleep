import Foundation

/// Abstraction over the OS sleep-prevention mechanism so logic is testable.
public protocol SleepBlocking: AnyObject {
    /// Begin blocking sleep. Returns an opaque token to release later, or `nil`
    /// if the block could not be acquired (e.g. the user cancelled the admin
    /// authorization required to disable sleep).
    func begin(reason: String) -> Int?
    /// Release a previously acquired block.
    func end(token: Int)

    /// Begin blocking sleep WITHOUT any chance of user interaction (no admin
    /// prompt). Used by unattended paths (Smart re-engage at 3 AM). Returns
    /// nil on failure — implementations must fail fast rather than prompt.
    func beginNonInteractive(reason: String) -> Int?

    /// Release a block WITHOUT any chance of user interaction. Returns false
    /// on failure — implementations must fail fast rather than prompt.
    func endNonInteractive(token: Int) -> Bool
}

public extension SleepBlocking {
    // Defaults for implementations whose begin/end never prompt anyway.
    func beginNonInteractive(reason: String) -> Int? { begin(reason: reason) }
    func endNonInteractive(token: Int) -> Bool { end(token: token); return true }
}
