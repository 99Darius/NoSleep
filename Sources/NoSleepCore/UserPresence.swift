import CoreGraphics
import Foundation

/// Seam for "is a human using this Mac right now" (CoreGraphics in the app,
/// a fake in tests).
public protocol UserPresenceProviding: AnyObject {
    /// Seconds since the last human input event (key, mouse, trackpad).
    func secondsSinceLastUserInput() -> TimeInterval
    /// Whether the built-in/main display is asleep (dark).
    func isDisplayAsleep() -> Bool
}

/// Real implementation, backed by the HID event system and display state.
///
/// The display is the primary presence signal: a lit screen means someone is
/// looking at it — reading or watching a video produces no input for long
/// stretches, which is exactly how input recency alone mis-fired auto-off with
/// the user sitting right there (live bug 2026-08-10). A dark screen means the
/// lid is shut or macOS's own idle timer already decided the user left.
/// HID input stays as a backstop for the moments around the transition.
public final class SystemUserPresence: UserPresenceProviding {
    public init() {}

    public func secondsSinceLastUserInput() -> TimeInterval {
        // kCGAnyInputEventType — no Swift constant is exported for it.
        // `.hidSystemState` is the hardware-level source, so it keeps counting
        // with the display asleep or the screen locked.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    public func isDisplayAsleep() -> Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }
}
