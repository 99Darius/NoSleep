import Foundation
import NoSleepCore

final class DispatchTimerScheduler: TimerScheduling {
    private var source: DispatchSourceTimer?

    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + seconds)
        t.setEventHandler(handler: work)
        t.resume()
        source = t
    }

    func cancel() {
        source?.cancel()
        source = nil
    }
}
