import Foundation

public protocol TypingProtocol: Sendable {
    func sendTypingNotice(roomID: String, isTyping: Bool) async throws
    func typingUsersStream(roomID: String) -> AsyncStream<[NebUser]>
}
