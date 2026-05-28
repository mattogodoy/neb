import Foundation
import NebCore

final class MockTimelineService: TimelineProtocol, @unchecked Sendable {
    var messages: [String: [NebMessage]] = [:]
    var sentMessages: [(roomID: String, body: String)] = []
    var markedAsRead: [String] = []
    private var timelineContinuations: [String: AsyncStream<[NebMessage]>.Continuation] = [:]

    func messageStream(roomID: String) -> AsyncStream<[NebMessage]> {
        AsyncStream { continuation in
            self.timelineContinuations[roomID] = continuation
            continuation.yield(self.messages[roomID] ?? [])
        }
    }

    func send(roomID: String, body: String) async throws {
        sentMessages.append((roomID: roomID, body: body))
    }

    func sendReply(roomID: String, body: String, replyToEventID: String) async throws {}

    func edit(roomID: String, eventID: String, newBody: String) async throws {}

    func delete(roomID: String, eventID: String, reason: String?) async throws {}

    func react(roomID: String, eventID: String, emoji: String) async throws {
        toggledReactions.append((roomID: roomID, eventID: eventID, emoji: emoji))
    }

    func paginateBackwards(roomID: String, count: UInt) async throws {}

    func markAsRead(roomID: String) async throws {
        markedAsRead.append(roomID)
    }

    func sendImage(roomID: String, url: URL, caption: String?) async throws {}
    func sendFile(roomID: String, url: URL, caption: String?) async throws {}
    func sendVideo(roomID: String, url: URL, thumbnailURL: URL, caption: String?) async throws {}

    var toggledReactions: [(roomID: String, eventID: String, emoji: String)] = []

    func emitMessages(roomID: String, messages: [NebMessage]) {
        self.messages[roomID] = messages
        timelineContinuations[roomID]?.yield(messages)
    }
}

final class MockRoomsService: RoomsProtocol, @unchecked Sendable {
    var createdDMUserID: String?

    func createRoom(name: String?, topic: String?, isEncrypted: Bool, isDirect: Bool, inviteUserIDs: [String]) async throws -> String {
        return "!new-room:example.com"
    }

    func createDM(userID: String) async throws -> String {
        createdDMUserID = userID
        return "!new-dm-room:example.com"
    }

    func joinRoom(roomIDOrAlias: String) async throws {}
    func leaveRoom(roomID: String) async throws {}
    func setRoomName(roomID: String, name: String) async throws {}
    func setRoomTopic(roomID: String, topic: String) async throws {}
    func setRoomAvatar(roomID: String, data: Data, mimeType: String) async throws {}

    func roomInfo(roomID: String) async throws -> NebRoom {
        NebRoom(id: roomID, name: "Mock Room")
    }
}
