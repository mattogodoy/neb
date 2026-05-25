import Foundation

public struct NebReaction: Equatable, Sendable {
    public let emoji: String
    public let count: Int
    public let senderIDs: [String]
    public let includesMe: Bool

    public init(emoji: String, count: Int, senderIDs: [String], includesMe: Bool) {
        self.emoji = emoji
        self.count = count
        self.senderIDs = senderIDs
        self.includesMe = includesMe
    }
}
