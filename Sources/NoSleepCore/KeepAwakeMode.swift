import Foundation

/// How keep-awake behaves while active.
/// - smart: stay awake while coding agents are working; once they go idle,
///   release the block so the Mac can sleep (default).
/// - absolute: never sleep until the user turns NoSleep off.
public enum KeepAwakeMode: String, Codable {
    case smart
    case absolute
}
