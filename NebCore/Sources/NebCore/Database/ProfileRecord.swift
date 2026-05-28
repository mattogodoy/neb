import Foundation
import GRDB

public struct ProfileRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "profiles"

    public var userID: String
    public var displayName: String?
    public var avatarURL: String?

    public init(userID: String, displayName: String? = nil, avatarURL: String? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}
