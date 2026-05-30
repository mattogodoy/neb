import Foundation
import GRDB

public struct MemberRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "members"

    public var roomID: String
    public var userID: String
    public var displayName: String?
    public var avatarURL: String?
    public var membership: String  // "join", "invite", "leave", "ban", "knock"

    public init(
        roomID: String,
        userID: String,
        displayName: String? = nil,
        avatarURL: String? = nil,
        membership: String = "join"
    ) {
        self.roomID = roomID
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.membership = membership
    }
}
