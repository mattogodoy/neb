import Foundation
import GRDB

public struct ReadReceiptRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "read_receipts"

    public var roomID: String
    public var userID: String
    public var eventID: String

    public init(roomID: String, userID: String, eventID: String) {
        self.roomID = roomID
        self.userID = userID
        self.eventID = eventID
    }
}
