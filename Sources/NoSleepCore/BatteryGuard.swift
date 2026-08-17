import Foundation
import IOKit.ps

/// The machine's power situation, reduced to the two facts that matter here.
public struct BatteryState: Equatable {
    /// True when running on the internal battery (not plugged in).
    public var isOnBattery: Bool
    /// Remaining charge, 0–100.
    public var percent: Int

    public init(isOnBattery: Bool, percent: Int) {
        self.isOnBattery = isOnBattery
        self.percent = percent
    }
}

/// Last-resort brake on the sleep block.
///
/// Every other part of NoSleep decides whether the *user* wants the Mac awake.
/// This one decides whether the Mac can afford it. On 2026-08-16→17 a stuck
/// display assertion kept Smart mode holding the block on battery all night;
/// the Mac drew down to zero, hard-shut-down, and came back reporting battery
/// health "Poor" where it had said "Good". A keep-awake utility that flattens
/// the battery has done more damage than the sleep it prevented was worth.
public enum BatteryGuard {
    /// Release the block at or below this charge, in any mode.
    public static let releasePercent = 10
    /// Only re-engage once the battery has genuinely recovered. The gap between
    /// the two thresholds is what stops a Mac parked at the line from flapping
    /// the block once a minute.
    public static let resumePercent = 25

    /// Whether an engaged sleep block must be released right now.
    /// An unreadable power source (desktop Mac, external UPS) is never treated
    /// as an empty battery.
    public static func shouldRelease(_ state: BatteryState?) -> Bool {
        guard let state, state.isOnBattery else { return false }
        return state.percent <= releasePercent
    }

    /// Whether a block released for low battery may be re-engaged. Reading the
    /// battery is best-effort, so an unreadable one resumes rather than leaving
    /// keep-awake switched off forever with no way for the user to tell why.
    public static func shouldResume(_ state: BatteryState?) -> Bool {
        guard let state else { return true }
        if !state.isOnBattery { return true }
        return state.percent >= resumePercent
    }

    /// Reads the internal battery. Returns nil when there isn't one, or when
    /// the power-source snapshot can't be parsed.
    public static func read() -> BatteryState? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
                  let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0
            else { continue }
            let state = desc[kIOPSPowerSourceStateKey as String] as? String
            return BatteryState(isOnBattery: state == kIOPSBatteryPowerValue,
                                percent: Int((Double(current) / Double(max) * 100).rounded()))
        }
        return nil
    }
}
