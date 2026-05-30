import Foundation

/// Abstraction over the OS sleep-prevention mechanism so logic is testable.
public protocol SleepBlocking: AnyObject {
    /// Begin blocking idle system sleep. Returns an opaque token to release later.
    func begin(reason: String) -> Int
    /// Release a previously acquired block.
    func end(token: Int)
}
