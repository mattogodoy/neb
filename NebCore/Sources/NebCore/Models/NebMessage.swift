import Foundation

public struct NebMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let roomID: String
    public let senderID: String
    public var senderDisplayName: String
    public var body: String
    public var timestamp: Date
    public var isOutgoing: Bool

    public init(
        id: String,
        roomID: String,
        senderID: String,
        senderDisplayName: String,
        body: String,
        timestamp: Date,
        isOutgoing: Bool
    ) {
        self.id = id
        self.roomID = roomID
        self.senderID = senderID
        self.senderDisplayName = senderDisplayName
        self.body = body
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
    }
}
