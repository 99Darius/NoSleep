import Foundation

public final class StateStore {
    public static let suiteName = "com.nosleep.shared"

    private let defaults: UserDefaults
    private let stateKey = "state"
    private let pidKey = "pid"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Convenience for production use against the shared suite.
    public static func shared() -> StateStore {
        StateStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    public func save(_ state: NoSleepState, pid: Int32) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
            defaults.set(Int(pid), forKey: pidKey)
        }
    }

    public func load() -> NoSleepState {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(NoSleepState.self, from: data)
        else { return .inactive }
        return state
    }

    public func loadPID() -> Int? {
        let p = defaults.integer(forKey: pidKey)
        return p == 0 ? nil : p
    }

    // MARK: - Agent heartbeat (`nosleep ping`)

    private var heartbeatKey: String { "lastHeartbeat" }

    public func saveHeartbeat(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: heartbeatKey)
    }

    public func loadHeartbeat() -> Date? {
        let t = defaults.double(forKey: heartbeatKey)
        return t == 0 ? nil : Date(timeIntervalSince1970: t)
    }

    // MARK: - Pending "while you were away" recap

    private var recapAtKey: String { "pendingRecapAt" }
    private var recapAgentsKey: String { "pendingRecapAgents" }

    public func savePendingRecap(_ recap: PendingRecap) {
        defaults.set(recap.sleptAt.timeIntervalSince1970, forKey: recapAtKey)
        defaults.set(recap.agents, forKey: recapAgentsKey)
    }

    public func loadPendingRecap() -> PendingRecap? {
        let t = defaults.double(forKey: recapAtKey)
        guard t != 0 else { return nil }
        let agents = defaults.stringArray(forKey: recapAgentsKey) ?? []
        return PendingRecap(sleptAt: Date(timeIntervalSince1970: t), agents: agents)
    }

    public func clearPendingRecap() {
        defaults.removeObject(forKey: recapAtKey)
        defaults.removeObject(forKey: recapAgentsKey)
    }
}

/// A Smart auto-off that fired while the screen was dark, waiting to be
/// recapped to the user the next time the display wakes.
public struct PendingRecap: Equatable {
    public let sleptAt: Date
    public let agents: [String]

    public init(sleptAt: Date, agents: [String]) {
        self.sleptAt = sleptAt
        self.agents = agents
    }
}
