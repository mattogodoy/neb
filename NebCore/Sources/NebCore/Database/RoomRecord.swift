import Foundation
import GRDB

public struct RoomRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "rooms"

    public var roomID: String
    public var name: String
    public var avatarURL: String?
    public var unreadCount: Int
    public var isDirect: Bool
    public var directUserID: String?
    public var memberCount: Int

    public init(
        roomID: String,
        name: String,
        avatarURL: String? = nil,
        unreadCount: Int = 0,
        isDirect: Bool = false,
        directUserID: String? = nil,
        memberCount: Int = 0
    ) {
        self.roomID = roomID
        self.name = name
        self.avatarURL = avatarURL
        self.unreadCount = unreadCount
        self.isDirect = isDirect
        self.directUserID = directUserID
        self.memberCount = memberCount
    }
}
