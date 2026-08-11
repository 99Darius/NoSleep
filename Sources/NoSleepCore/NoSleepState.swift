import Foundation

public struct NoSleepState: Equatable, Codable {
    public var isActive: Bool
    public var expiresAt: Date?
    /// Smart NoSleep only: armed but currently letting the Mac sleep because
    /// agents are idle. The block re-engages when agents resume. Optional so
    /// state JSON persisted by older builds still decodes.
    public var dozing: Bool?

    public init(isActive: Bool, expiresAt: Date? = nil, dozing: Bool? = nil) {
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.dozing = dozing
    }

    public static let inactive = NoSleepState(isActive: false, expiresAt: nil)
}
