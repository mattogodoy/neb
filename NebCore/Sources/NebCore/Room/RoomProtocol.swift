import Foundation

public protocol RoomProtocol: Sendable {
    func timelineStream(roomID: String) -> AsyncStream<[NebMessage]>
    func sendMessage(roomID: String, body: String) async throws
    func sendReadReceipt(roomID: String, eventID: String) async throws
    func createDM(userID: String) async throws -> String
    func paginateBackwards(roomID: String, count: UInt) async throws
    func toggleReaction(roomID: String, eventID: String, emoji: String) async throws
    func editMessage(roomID: String, eventID: String, newBody: String) async throws
}
