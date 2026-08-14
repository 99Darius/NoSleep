import Foundation

/// Formats the "while you were away" recap shown the first time the screen
/// comes back on after Smart NoSleep released the keep-awake block.
public enum SmartRecap {
    public static func message(sleptAt: Date,
                               graceMinutes: Int,
                               agents: [String],
                               timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        formatter.timeZone = timeZone
        let time = formatter.string(from: sleptAt)
        var text = "Smart NoSleep let your Mac sleep at \(time) after \(graceMinutes) min of quiet."
        if !agents.isEmpty {
            text += " Last running: \(agents.joined(separator: ", "))."
        }
        return text
    }
}
