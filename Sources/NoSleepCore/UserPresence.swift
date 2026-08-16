import CoreGraphics
import Foundation
import IOKit
import IOKit.pwr_mgt

/// Seam for "is a human using this Mac right now" (CoreGraphics in the app,
/// a fake in tests).
public protocol UserPresenceProviding: AnyObject {
    /// Seconds since the last human input event (key, mouse, trackpad).
    func secondsSinceLastUserInput() -> TimeInterval
    /// Whether the built-in/main display is asleep (dark).
    func isDisplayAsleep() -> Bool
    /// One-line trace of the raw signals behind `isDisplayAsleep()`, for logs.
    func signalTrace() -> String
}

public extension UserPresenceProviding {
    func signalTrace() -> String { "" }
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
        DisplayJudge.isAsleep(currentSignals())
    }

    /// The raw signals behind the verdict. The 2026-08-16 miss went unnoticed
    /// for a night because the log recorded only the verdict, not what fed it.
    public func currentSignals() -> DisplaySignals {
        DisplaySignals(
            notifiedAsleep: notifiedDisplayAsleep,
            cgReportsAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0,
            displaysAllOff: Self.allPanelsOff(),
            displaySleepAssertionHeld: Self.displaySleepAssertionHeld(),
            hidIdleSeconds: secondsSinceLastUserInput(),
            displaySleepTimeout: displaySleepTimeout())
    }

    /// Whether anything currently holds a "keep the display awake" assertion —
    /// a video player, a video call, a presentation. While one is held, macOS's
    /// display-idle timer is suspended, so keyboard silence says nothing about
    /// whether someone is watching.
    public static func displaySleepAssertionHeld() -> Bool {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&assertions) == kIOReturnSuccess,
              let dict = assertions?.takeRetainedValue() as? [String: Any]
        else { return false }
        for key in [kIOPMAssertionTypePreventUserIdleDisplaySleep,
                    kIOPMAssertionTypeNoDisplaySleep] {
            if let level = dict[key as String] as? Int, level > 0 { return true }
        }
        return false
    }

    /// Reads every display controller's power state from IORegistry.
    /// Returns nil when no controller can be read (older/Intel Macs), true only
    /// when every panel is powered down. Checking *all* panels is what makes
    /// external-monitor setups behave: a lit external display means the user is
    /// there, even with the laptop lid shut.
    public static func allPanelsOff() -> Bool? {
        var states: [Int] = []
        for className in ["AppleCLCD2", "AppleCLCD", "IODisplayWrangler"] {
            guard let matching = IOServiceMatching(className) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
            else { continue }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                guard let props = IORegistryEntryCreateCFProperty(
                        service, "IOPowerManagement" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? [String: Any],
                      let current = props["CurrentPowerState"] as? Int
                else { continue }
                states.append(current)
            }
            if !states.isEmpty { break }   // first class that answers wins
        }
        guard !states.isEmpty else { return nil }
        return states.allSatisfy { $0 == 0 }
    }

    public func signalTrace() -> String {
        let s = currentSignals()
        let notified = s.notifiedAsleep.map { $0 ? "asleep" : "awake" } ?? "unknown"
        let panels = s.displaysAllOff.map { $0 ? "all-off" : "lit" } ?? "unknown"
        return "notified=\(notified) cg=\(s.cgReportsAsleep ? "asleep" : "awake")"
            + " panels=\(panels) idle=\(Int(s.hidIdleSeconds))s/\(Int(s.displaySleepTimeout))s"
    }

    /// The user's active `pmset displaysleep` setting, in seconds (0 = never).
    /// Re-read every minute: unplugging a MacBook can drop it from 60 minutes
    /// (adapter) to 2 (battery), and a stale value there feeds a wrong verdict
    /// straight into the countdown. The subprocess costs a few ms once a tick.
    private func displaySleepTimeout() -> TimeInterval {
        if let read = timeoutReadAt, Date().timeIntervalSince(read) < 60 {
            return cachedTimeout
        }
        timeoutReadAt = Date()
        cachedTimeout = Self.readDisplaySleepMinutes().map { TimeInterval($0) * 60 } ?? 0
        return cachedTimeout
    }

    /// Pulls `displaysleep` out of `pmset -g` output. Kept pure so the many
    /// shapes this output takes across Macs (desktop with no battery section,
    /// annotated values, "0" for never) can be tested without a machine that
    /// has them.
    public static func parseDisplaySleepMinutes(from output: String) -> Int? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let fields = rawLine.split(whereSeparator: \.isWhitespace)
            // Match the key exactly: `disksleep` also contains "sleep", and
            // several keys share prefixes.
            guard let keyIndex = fields.firstIndex(where: { $0 == "displaysleep" }),
                  keyIndex + 1 < fields.count,
                  let minutes = Int(fields[keyIndex + 1])
            else { continue }
            return minutes
        }
        return nil
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
        return parseDisplaySleepMinutes(from: out)
    }
}
