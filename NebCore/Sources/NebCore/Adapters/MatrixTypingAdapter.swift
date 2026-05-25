import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Typing")

public final class MatrixTypingAdapter: TypingServiceProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private let roomListServiceProvider: () -> RoomListService?

    public init(clientProvider: @escaping () -> Client?, roomListServiceProvider: @escaping () -> RoomListService?) {
        self.clientProvider = clientProvider
        self.roomListServiceProvider = roomListServiceProvider
    }

    public func sendTypingNotice(roomID: String, isTyping: Bool) async throws {
        guard let client = clientProvider() else { return }
        guard let room = try client.getRoom(roomId: roomID) else { return }
        try await room.typingNotice(isTyping: isTyping)
    }

    public func typingUsersStream(roomID: String) -> AsyncStream<[NebUser]> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            guard let client = self.clientProvider() else { return }
            guard let room = try? client.getRoom(roomId: roomID) else { return }

            let listener = NebTypingListener(roomID: roomID, room: room, continuation: continuation)
            let handle = room.subscribeToTypingNotifications(listener: listener)

            continuation.onTermination = { _ in
                // handle is captured here to keep it alive until the stream ends
                _ = handle
            }
        }
    }
}

private final class NebTypingListener: TypingNotificationsListener, @unchecked Sendable {
    private let roomID: String
    private let room: Room
    private let continuation: AsyncStream<[NebUser]>.Continuation

    init(roomID: String, room: Room, continuation: AsyncStream<[NebUser]>.Continuation) {
        self.roomID = roomID
        self.room = room
        self.continuation = continuation
    }

    func call(typingUserIds: [String]) {
        Task {
            var users: [NebUser] = []
            for userID in typingUserIds {
                var displayName: String? = nil
                var avatarURL: String? = nil

                if let members = try? await room.membersNoSync() {
                    while let chunk = members.nextChunk(chunkSize: 50) {
                        for member in chunk {
                            if member.userId == userID {
                                displayName = member.displayName
                                avatarURL = member.avatarUrl
                                break
                            }
                        }
                        if displayName != nil { break }
                    }
                }

                users.append(NebUser(
                    id: userID,
                    displayName: displayName,
                    avatarURL: avatarURL
                ))
            }
            continuation.yield(users)
        }
    }
}
