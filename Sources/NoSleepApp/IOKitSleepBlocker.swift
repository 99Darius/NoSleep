import Foundation
import IOKit.pwr_mgt
import NoSleepCore

final class IOKitSleepBlocker: SleepBlocking {
    private var assertions: [Int: IOPMAssertionID] = [:]
    private var nextKey = 1

    func begin(reason: String) -> Int {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        let key = nextKey; nextKey += 1
        if result == kIOReturnSuccess { assertions[key] = id }
        return key
    }

    func end(token: Int) {
        guard let id = assertions[token] else { return }
        IOPMAssertionRelease(id)
        assertions[token] = nil
    }
}
