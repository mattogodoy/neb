import Foundation
import NebCore

final class MockTimelineService: TimelineProtocol, @unchecked Sendable {
    var sentMessages: [(roomID: String, body: String)] = []
    var markedAsRead: [String] = []
    var toggledReactions: [(roomID: String, eventID: String, emoji: String)] = []
    var syncedRooms: [String] = []
    var stoppedRooms: [String] = []

    func startTimelineSync(roomID: String) async throws {
        syncedRooms.append(roomID)
    }

    func stopTimelineSync(roomID: String) async throws {
        stoppedRooms.append(roomID)
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

    func markAsRead(roomID: String) async throws {
        markedAsRead.append(roomID)
    }

    func sendImage(roomID: String, url: URL, caption: String?) async throws {}
    func sendFile(roomID: String, url: URL, caption: String?) async throws {}
    func sendVideo(roomID: String, url: URL, thumbnailURL: URL, caption: String?) async throws {}
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

    // Room list
    var rooms: [NebRoom] = []
    private var roomsContinuation: AsyncStream<[NebRoom]>.Continuation?

    @MainActor
    func roomListStream() -> AsyncStream<[NebRoom]> {
        AsyncStream { continuation in
            self.roomsContinuation = continuation
            continuation.yield(self.rooms)
        }
    }

    func emitRooms(_ rooms: [NebRoom]) {
        self.rooms = rooms
        roomsContinuation?.yield(rooms)
    }

    // Typing
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
