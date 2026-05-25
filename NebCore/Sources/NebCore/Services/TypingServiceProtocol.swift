import Foundation

public protocol TypingServiceProtocol: Sendable {
    func sendTypingNotice(roomID: String, isTyping: Bool) async throws
    func typingUsersStream(roomID: String) -> AsyncStream<[NebUser]>
}
