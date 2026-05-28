import Foundation
import GRDB

public struct ReactionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "reactions"

    public var eventID: String
    public var emoji: String
    public var senderID: String

    public init(eventID: String, emoji: String, senderID: String) {
        self.eventID = eventID
        self.emoji = emoji
        self.senderID = senderID
    }
}
