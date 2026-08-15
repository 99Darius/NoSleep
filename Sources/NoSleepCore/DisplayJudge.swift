import Foundation

/// Everything known about whether the screen is currently dark.
public struct DisplaySignals: Equatable {
    /// Latest NSWorkspace screensDidSleep/DidWake verdict; nil until one arrives.
    public var notifiedAsleep: Bool?
    /// `CGDisplayIsAsleep(CGMainDisplayID())`. Unreliable on Apple Silicon —
    /// it reported "awake" through a 4h45m display-off window on 2026-08-16.
    public var cgReportsAsleep: Bool
    /// Seconds since the last keyboard/trackpad event.
    public var hidIdleSeconds: TimeInterval
    /// The user's own `pmset displaysleep` timeout in seconds; 0 = never.
    public var displaySleepTimeout: TimeInterval

    public init(notifiedAsleep: Bool? = nil,
                cgReportsAsleep: Bool = false,
                hidIdleSeconds: TimeInterval = 0,
                displaySleepTimeout: TimeInterval = 0) {
        self.notifiedAsleep = notifiedAsleep
        self.cgReportsAsleep = cgReportsAsleep
        self.hidIdleSeconds = hidIdleSeconds
        self.displaySleepTimeout = displaySleepTimeout
    }
}

/// Decides "is the screen dark?" from several independent signals, because no
/// single one is trustworthy on its own.
public enum DisplayJudge {
    /// Any signal claiming darkness wins. Missing a dark screen is the costly
    /// error — it leaves the Mac awake all night, which is exactly what
    /// happened when CGDisplayIsAsleep was trusted alone.
    public static func isAsleep(_ s: DisplaySignals) -> Bool {
        if s.notifiedAsleep == true { return true }
        if s.cgReportsAsleep { return true }
        // Fallback for when the OS-level signals lie: once the user has been
        // idle longer than their own display-sleep timeout, macOS itself has
        // judged them away. `0` means "never sleep the display" — no verdict.
        if s.displaySleepTimeout > 0, s.hidIdleSeconds >= s.displaySleepTimeout { return true }
        return false
    }
}
