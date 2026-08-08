import CoreGraphics
import Foundation

/// Seam for "is a human using this Mac right now" (CoreGraphics in the app,
/// a fake in tests).
public protocol UserPresenceProviding: AnyObject {
    /// Seconds since the last human input event (key, mouse, trackpad).
    func secondsSinceLastUserInput() -> TimeInterval
}

/// Real implementation, backed by the HID event system.
///
/// `.hidSystemState` is the hardware-level source, so it keeps counting with
/// the display asleep or the screen locked. With the lid shut no input can
/// reach the Mac at all, which is exactly why this doubles as clamshell
/// detection: a closed lid means the idle time only ever grows.
public final class SystemUserPresence: UserPresenceProviding {
    public init() {}

    public func secondsSinceLastUserInput() -> TimeInterval {
        // kCGAnyInputEventType — no Swift constant is exported for it.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }
}
