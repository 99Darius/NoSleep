import Foundation

/// Single source of truth for the keep-awake state. Holds at most one block.
///
/// Concurrency: this type is not thread-safe by design. All calls are expected
/// to happen on the main thread — the timer fires on the main DispatchQueue, and
/// DistributedNotificationCenter observers and menu actions all run on main.
public final class AssertionManager {
    private let blocker: SleepBlocking
    private var token: Int?

    /// Called after every state change so the UI/store can refresh.
    public var onChange: (() -> Void)?

    public init(blocker: SleepBlocking) {
        self.blocker = blocker
    }

    public var isActive: Bool { token != nil }

    public func activate() {
        guard token == nil else { return }            // idempotent: no leak
        guard let t = blocker.begin(reason: "NoSleep active") else { return } // failed/cancelled
        token = t
        onChange?()
    }

    public func deactivate() {
        guard let t = token else { return }            // no-op when inactive
        blocker.end(token: t)
        token = nil
        onChange?()
    }

    public func toggle() {
        isActive ? deactivate() : activate()
    }

    /// Unattended activation (Smart re-engage): must never show a prompt.
    /// Returns whether the block is held afterwards.
    @discardableResult
    public func activateUnattended() -> Bool {
        if token != nil { return true }
        guard let t = blocker.beginNonInteractive(reason: "NoSleep active") else { return false }
        token = t
        onChange?()
        return true
    }

    /// Unattended release (Smart auto-off): must never show a prompt.
    /// On failure the token is kept — the block is still real, so the state
    /// must keep saying so. Returns whether the block is released afterwards.
    @discardableResult
    public func deactivateUnattended() -> Bool {
        guard let t = token else { return true }
        guard blocker.endNonInteractive(token: t) else { return false }
        token = nil
        onChange?()
        return true
    }
}
