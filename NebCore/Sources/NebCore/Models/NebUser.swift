import Foundation

public struct NebUser: Identifiable, Equatable, Sendable {
    public let id: String
    public var displayName: String?
    public var avatarURL: String?
    public var isVerified: Bool

    public init(
        id: String,
        displayName: String? = nil,
        avatarURL: String? = nil,
        isVerified: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isVerified = isVerified
    }
}
