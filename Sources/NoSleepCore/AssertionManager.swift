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
        token = blocker.begin(reason: "NoSleep active")
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
}
