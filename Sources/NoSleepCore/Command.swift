import Foundation

public enum Command: Equatable {
    case on
    case off
    case toggle
    case status
    case timer(TimeInterval)
    case ping

    /// Parse from CLI argv (excluding the program name).
    public static func parse(_ args: [String]) -> Command? {
        guard let first = args.first else { return nil }
        switch first {
        case "on": return .on
        case "off": return .off
        case "toggle": return .toggle
        case "status": return .status
        case "ping": return .ping
        case "timer":
            guard args.count >= 2, let secs = parseDuration(args[1]) else { return nil }
            return .timer(secs)
        default: return nil
        }
    }

    // MARK: - Notification payload encoding

    public var userInfo: [String: Any] {
        switch self {
        case .on: return ["action": "on"]
        case .off: return ["action": "off"]
        case .toggle: return ["action": "toggle"]
        case .status: return ["action": "status"]
        case .timer(let s): return ["action": "timer", "seconds": s]
        case .ping: return ["action": "ping"]
        }
    }

    public init?(userInfo: [AnyHashable: Any]?) {
        guard let action = userInfo?["action"] as? String else { return nil }
        switch action {
        case "on": self = .on
        case "off": self = .off
        case "toggle": self = .toggle
        case "status": self = .status
        case "timer":
            guard let s = userInfo?["seconds"] as? TimeInterval else { return nil }
            self = .timer(s)
        case "ping": self = .ping
        default: return nil
        }
    }
}

/// Parse durations like "90s", "15m", "1h", "2h".
public func parseDuration(_ text: String) -> TimeInterval? {
    guard let unit = text.last, let value = Double(text.dropLast()) else { return nil }
    let seconds: TimeInterval
    switch unit {
    case "s": seconds = value
    case "m": seconds = value * 60
    case "h": seconds = value * 3600
    default: return nil
    }
    guard seconds >= 0 else { return nil }
    return seconds
}

/// Format seconds compactly: 3720 -> "1h2m".
public func formatDuration(seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    var out = ""
    if h > 0 { out += "\(h)h" }
    if m > 0 { out += "\(m)m" }
    if s > 0 || out.isEmpty { out += "\(s)s" }
    return out
}
