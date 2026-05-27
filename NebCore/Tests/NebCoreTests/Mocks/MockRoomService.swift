import Foundation
@testable import NebCore

final class MockRoomService: RoomProtocol, @unchecked Sendable {
    var messages: [String: [NebMessage]] = [:]
    var sentMessages: [(roomID: String, body: String)] = []
    var readReceipts: [(roomID: String, eventID: String)] = []
    var createdDMUserID: String?
    private var timelineContinuations: [String: AsyncStream<[NebMessage]>.Continuation] = [:]

    func timelineStream(roomID: String) -> AsyncStream<[NebMessage]> {
        AsyncStream { continuation in
            self.timelineContinuations[roomID] = continuation
            continuation.yield(self.messages[roomID] ?? [])
        }
    }

    func sendMessage(roomID: String, body: String) async throws {
        sentMessages.append((roomID: roomID, body: body))
    }

    func sendReadReceipt(roomID: String, eventID: String) async throws {
        readReceipts.append((roomID: roomID, eventID: eventID))
    }

    func createDM(userID: String) async throws -> String {
        createdDMUserID = userID
        return "!new-dm-room:example.com"
    }

    func paginateBackwards(roomID: String, count: UInt) async throws {}

    var toggledReactions: [(roomID: String, eventID: String, emoji: String)] = []

    func toggleReaction(roomID: String, eventID: String, emoji: String) async throws {
        toggledReactions.append((roomID: roomID, eventID: eventID, emoji: emoji))
    }

    func editMessage(roomID: String, eventID: String, newBody: String) async throws {}

    func emitMessages(roomID: String, messages: [NebMessage]) {
        self.messages[roomID] = messages
        timelineContinuations[roomID]?.yield(messages)
    }
}
