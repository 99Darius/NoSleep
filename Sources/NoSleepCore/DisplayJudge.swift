import Foundation

/// Everything known about whether the screen is currently dark.
public struct DisplaySignals: Equatable {
    /// Latest NSWorkspace screensDidSleep/DidWake verdict; nil until one arrives.
    public var notifiedAsleep: Bool?
    /// `CGDisplayIsAsleep(CGMainDisplayID())`. Unreliable on Apple Silicon —
    /// it reported "awake" through a 4h45m display-off window on 2026-08-16.
    public var cgReportsAsleep: Bool
    /// Every attached panel's power state read straight from IORegistry:
    /// true = all dark, false = at least one lit, nil = unreadable on this Mac.
    /// This is the signal that gets multi-display right — an external monitor
    /// still lit means the user is there even if the laptop's lid is shut.
    public var displaysAllOff: Bool?
    /// Whether any process holds a `PreventUserIdleDisplaySleep` assertion —
    /// a video player, a call, a slide deck. While one is held macOS's idle
    /// timer is not running, so "no input for a while" proves nothing about
    /// whether anyone is watching.
    public var displaySleepAssertionHeld: Bool
    /// Seconds since the last keyboard/trackpad event.
    public var hidIdleSeconds: TimeInterval
    /// The user's own `pmset displaysleep` timeout in seconds; 0 = never.
    public var displaySleepTimeout: TimeInterval

    /// Used instead of the timeout when the display is set to never sleep or
    /// there is no display at all (headless Mac mini) — without it, Smart mode
    /// could never conclude the user had left on those machines.
    public static let headlessIdleFallback: TimeInterval = 30 * 60

    /// Past this much input silence, nothing gets to claim the user is present.
    ///
    /// A lit panel and a held display-sleep assertion are both evidence of
    /// presence right up until they aren't: a stuck recording assertion from a
    /// transcription app pinned the display on for a whole night on
    /// 2026-08-16→17, so NoSleep held the sleep block until the battery hit
    /// zero and the Mac hard-shut-down. A person watching a film still exists —
    /// they shift, they scrub, they touch the trackpad. Hours of literally zero
    /// events do not happen with someone in the chair, whatever the screen says.
    public static let absenceCeiling: TimeInterval = 2 * 3600

    /// The ceiling for these signals. Someone who set a 3-hour display-sleep
    /// timeout has told macOS how long their idle stretches run; respect that
    /// rather than overruling them after two hours. Capped so a "never sleep
    /// the display" setting can't push the ceiling out of reach.
    public static func absenceCeiling(for signals: DisplaySignals) -> TimeInterval {
        let scaled = 2 * signals.displaySleepTimeout
        return min(max(absenceCeiling, scaled), 6 * 3600)
    }

    public init(notifiedAsleep: Bool? = nil,
                cgReportsAsleep: Bool = false,
                displaysAllOff: Bool? = nil,
                displaySleepAssertionHeld: Bool = false,
                hidIdleSeconds: TimeInterval = 0,
                displaySleepTimeout: TimeInterval = 0) {
        self.displaySleepAssertionHeld = displaySleepAssertionHeld
        self.notifiedAsleep = notifiedAsleep
        self.cgReportsAsleep = cgReportsAsleep
        self.displaysAllOff = displaysAllOff
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
        // 1. Anything reporting darkness is believed. Missing a dark screen
        // costs a whole night of the Mac running hot with the lid shut.
        if s.displaysAllOff == true { return true }
        if s.notifiedAsleep == true { return true }
        if s.cgReportsAsleep { return true }

        // 2. Beyond the absence ceiling nothing gets to vouch for the user.
        // A lit screen is only evidence of presence while presence is still
        // physically plausible; after hours without a single event it is
        // evidence of a stuck assertion or a monitor nobody is sitting at.
        // Skipping this is what drained the battery flat on 2026-08-17.
        if s.hidIdleSeconds >= DisplaySignals.absenceCeiling(for: s) { return true }

        // 3. Live hardware evidence of a lit panel outranks the heuristic.
        if s.displaysAllOff == false { return false }

        // 4. Something is deliberately holding the screen on — a film, a video
        // call, a presentation. macOS's idle timer is suspended, so no amount of
        // keyboard silence implies the user left. Inferring absence here is the
        // 2026-08-07 / 08-10 complaint: a "letting your Mac sleep" notice in the
        // face of someone who is sitting right there watching.
        if s.displaySleepAssertionHeld { return false }

        // 5. Nothing is holding the screen on, so macOS's own idle timer is
        // running. Once the user has been idle past it, the screen is dark
        // whatever the other signals claim — that claim is what kept the Mac
        // awake all night on 2026-08-16. With no timeout to go by (display set
        // to never sleep, or a headless Mac) fall back to a conservative window
        // so Smart mode still works on those machines.
        let threshold = s.displaySleepTimeout > 0
            ? s.displaySleepTimeout
            : DisplaySignals.headlessIdleFallback
        return s.hidIdleSeconds >= threshold
    }
}
