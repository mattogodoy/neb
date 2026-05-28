import Foundation

public enum SendStatus: Equatable, Sendable {
    case sending
    case sent
    case failed
}

public struct ReadReceipt: Equatable, Sendable {
    public let userID: String
    public let displayName: String
    public let avatarURL: String?

    public init(userID: String, displayName: String, avatarURL: String? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}

public enum MessageGroupPosition: Sendable {
    case alone, first, middle, last
}

public struct MessageLayout: Sendable, Equatable {
    public let groupPosition: MessageGroupPosition
    public let showDaySeparator: Bool

    public init(groupPosition: MessageGroupPosition, showDaySeparator: Bool) {
        self.groupPosition = groupPosition
        self.showDaySeparator = showDaySeparator
    }
}

public struct NebMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let roomID: String
    public let senderID: String
    public var senderDisplayName: String
    public var senderAvatarURL: String?
    public var body: String
    public var formattedBody: String?
    public var timestamp: Date
    public var isOutgoing: Bool
    public var sendStatus: SendStatus
    public var readReceipts: [ReadReceipt]
    public var reactions: [NebReaction]
    public var isEdited: Bool
    public var isEditable: Bool
    public var isEmojiOnly: Bool

    public init(
        id: String,
        roomID: String,
        senderID: String,
        senderDisplayName: String,
        senderAvatarURL: String? = nil,
        body: String,
        formattedBody: String? = nil,
        timestamp: Date,
        isOutgoing: Bool,
        sendStatus: SendStatus = .sent,
        readReceipts: [ReadReceipt] = [],
        reactions: [NebReaction] = [],
        isEdited: Bool = false,
        isEditable: Bool = false,
        isEmojiOnly: Bool = false
    ) {
        self.id = id
        self.roomID = roomID
        self.senderID = senderID
        self.senderDisplayName = senderDisplayName
        self.senderAvatarURL = senderAvatarURL
        self.body = body
        self.formattedBody = formattedBody
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
        self.sendStatus = sendStatus
        self.readReceipts = readReceipts
        self.reactions = reactions
        self.isEdited = isEdited
        self.isEditable = isEditable
        self.isEmojiOnly = isEmojiOnly
    }
}

extension String {
    public var isEmojiOnly: Bool {
        guard !isEmpty && count <= 3 else { return false }
        return allSatisfy { $0.isEmoji }
    }
}

extension Character {
    public var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && scalar.value > 0x23
    }
}
