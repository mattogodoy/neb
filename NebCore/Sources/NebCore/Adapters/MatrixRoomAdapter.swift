import Foundation
import MatrixRustSDK

public final class MatrixRoomAdapter: RoomServiceProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?

    public init(clientProvider: @escaping () -> Client?) {
        self.clientProvider = clientProvider
    }

    public func timelineStream(roomID: String) -> AsyncStream<[NebMessage]> {
        AsyncStream { continuation in
            // Timeline observation will be wired during integration
        }
    }

    public func sendMessage(roomID: String, body: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        let timeline = try await room.timeline()
        let content = messageEventContentFromMarkdown(md: body)
        let _ = try await timeline.send(msg: content)
    }

    public func sendReadReceipt(roomID: String, eventID: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        let timeline = try await room.timeline()
        try await timeline.sendReadReceipt(receiptType: .read, eventId: eventID)
    }

    public func createDM(userID: String) async throws -> String {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }

        if let existing = try client.getDmRoom(userId: userID) {
            return existing.id()
        }

        let params = CreateRoomParameters(
            name: nil,
            topic: nil,
            isEncrypted: true,
            isDirect: true,
            visibility: .private,
            preset: .trustedPrivateChat,
            invite: [userID],
            avatar: nil,
            powerLevelContentOverride: nil
        )
        return try await client.createRoom(request: params)
    }

    public func paginateBackwards(roomID: String, count: UInt) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        let timeline = try await room.timeline()
        let _ = try await timeline.paginateBackwards(numEvents: UInt16(min(count, UInt(UInt16.max))))
    }
}
