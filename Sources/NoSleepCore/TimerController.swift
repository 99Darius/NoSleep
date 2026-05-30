import Foundation

public protocol TimerScheduling: AnyObject {
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void)
    func cancel()
}

public final class TimerController {
    private let scheduler: TimerScheduling
    private let onExpire: () -> Void

    public init(scheduler: TimerScheduling, onExpire: @escaping () -> Void) {
        self.scheduler = scheduler
        self.onExpire = onExpire
    }

    /// Replaces any pending timer (cancel-before-set).
    public func start(seconds: TimeInterval) {
        scheduler.cancel()
        scheduler.schedule(after: seconds) { [weak self] in
            self?.onExpire()
        }
    }

    public func cancel() {
        scheduler.cancel()
    }
}
