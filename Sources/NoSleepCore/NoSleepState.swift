import Foundation

public struct NoSleepState: Equatable, Codable {
    public var isActive: Bool
    public var expiresAt: Date?

    public init(isActive: Bool, expiresAt: Date? = nil) {
        self.isActive = isActive
        self.expiresAt = expiresAt
    }

    public static let inactive = NoSleepState(isActive: false, expiresAt: nil)
}
