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
/// Live miss 2026-08-16: `CGDisplayIsAsleep` reported "awake" for the whole
/// 4h45m the screen was actually off (Apple Silicon, macOS 26) — the countdown
/// never advanced and the Mac stayed awake all night. It is now only one of
/// three signals; see `DisplayJudge`.
public final class SystemUserPresence: UserPresenceProviding {
    /// Set by the app from NSWorkspace screensDidSleep/DidWake, the signal that
    /// actually tracks macOS's own "Display is turned off/on" events.
    public var notifiedDisplayAsleep: Bool?

    private var cachedTimeout: TimeInterval = 0
    private var timeoutReadAt: Date?

    public init() {}

    public func secondsSinceLastUserInput() -> TimeInterval {
        // kCGAnyInputEventType — no Swift constant is exported for it.
        // `.hidSystemState` is the hardware-level source, so it keeps counting
        // with the display asleep or the screen locked.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    public func isDisplayAsleep() -> Bool {
        DisplayJudge.isAsleep(DisplaySignals(
            notifiedAsleep: notifiedDisplayAsleep,
            cgReportsAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0,
            hidIdleSeconds: secondsSinceLastUserInput(),
            displaySleepTimeout: displaySleepTimeout()))
    }

    /// The user's active `pmset displaysleep` setting, in seconds (0 = never).
    /// Re-read every 10 minutes: it changes rarely, but it does change when the
    /// Mac switches between battery and power adapter.
    private func displaySleepTimeout() -> TimeInterval {
        if let read = timeoutReadAt, Date().timeIntervalSince(read) < 600 {
            return cachedTimeout
        }
        timeoutReadAt = Date()
        cachedTimeout = Self.readDisplaySleepMinutes().map { TimeInterval($0) * 60 } ?? 0
        return cachedTimeout
    }

    public static func readDisplaySleepMinutes() -> Int? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-g"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return nil }
        for line in out.split(separator: "\n") where line.contains("displaysleep") {
            return line.split(separator: " ").compactMap { Int($0) }.first
        }
        return nil
    }
}
