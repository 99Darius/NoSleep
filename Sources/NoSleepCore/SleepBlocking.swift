import Foundation

/// Abstraction over the OS sleep-prevention mechanism so logic is testable.
public protocol SleepBlocking: AnyObject {
    /// Begin blocking sleep. Returns an opaque token to release later, or `nil`
    /// if the block could not be acquired (e.g. the user cancelled the admin
    /// authorization required to disable sleep).
    func begin(reason: String) -> Int?
    /// Release a previously acquired block.
    func end(token: Int)
}
