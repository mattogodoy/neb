import Foundation

public struct NebRoom: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var lastMessage: String?
    public var lastMessageTimestamp: Date?
    public var unreadCount: UInt
    public var isDirect: Bool
    public var memberCount: UInt

    public init(
        id: String,
        name: String,
        lastMessage: String? = nil,
        lastMessageTimestamp: Date? = nil,
        unreadCount: UInt = 0,
        isDirect: Bool = false,
        memberCount: UInt = 0
    ) {
        self.id = id
        self.name = name
        self.lastMessage = lastMessage
        self.lastMessageTimestamp = lastMessageTimestamp
        self.unreadCount = unreadCount
        self.isDirect = isDirect
        self.memberCount = memberCount
    }
}
