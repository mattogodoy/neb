import Foundation
@testable import NebCore

final class MockTypingService: TypingServiceProtocol, @unchecked Sendable {
    var typingNotices: [(roomID: String, isTyping: Bool)] = []
    private var typingContinuations: [String: AsyncStream<[NebUser]>.Continuation] = [:]

    func sendTypingNotice(roomID: String, isTyping: Bool) async throws {
        typingNotices.append((roomID: roomID, isTyping: isTyping))
    }

    func typingUsersStream(roomID: String) -> AsyncStream<[NebUser]> {
        AsyncStream { continuation in
            self.typingContinuations[roomID] = continuation
            continuation.yield([])
        }
    }

    func emitTypingUsers(roomID: String, users: [NebUser]) {
        typingContinuations[roomID]?.yield(users)
    }
}
