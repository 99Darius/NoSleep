import Foundation

/// Parsing of `pmset -g` output, kept pure and in core so it can be tested
/// against the shapes other Macs produce.
public enum PMSetOutput {
    /// Whether `pmset -g` reports system sleep as disabled.
    ///
    /// The key is printed as `SleepDisabled`, tab-separated — NOT the
    /// `disablesleep` spelling used to *set* it. Matching the setter's spelling
    /// silently never matched, so NoSleep could never detect a sleep block left
    /// behind by a crash or force-quit (fixed 2026-08-16).
    public static func sleepDisabled(from output: String) -> Bool {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let keyIndex = fields.firstIndex(where: { $0 == "SleepDisabled" }),
                  keyIndex + 1 < fields.count
            else { continue }
            return fields[keyIndex + 1] == "1"
        }
        return false
    }
}
