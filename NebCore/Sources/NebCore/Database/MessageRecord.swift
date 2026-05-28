import Foundation
import GRDB

public struct MessageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "messages"

    public var eventID: String
    public var roomID: String
    public var senderID: String
    public var body: String
    public var formattedBody: String?
    public var timestamp: Double
    public var isEdited: Bool
    public var sendStatus: String
    public var transactionID: String?

    public init(
        eventID: String,
        roomID: String,
        senderID: String,
        body: String,
        formattedBody: String? = nil,
        timestamp: Double,
        isEdited: Bool = false,
        sendStatus: String = "sent",
        transactionID: String? = nil
    ) {
        self.eventID = eventID
        self.roomID = roomID
        self.senderID = senderID
        self.body = body
        self.formattedBody = formattedBody
        self.timestamp = timestamp
        self.isEdited = isEdited
        self.sendStatus = sendStatus
        self.transactionID = transactionID
    }
}
