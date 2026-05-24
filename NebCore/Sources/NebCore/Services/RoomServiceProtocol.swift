import Foundation

public protocol RoomServiceProtocol: Sendable {
    func timelineStream(roomID: String) -> AsyncStream<[NebMessage]>
    func sendMessage(roomID: String, body: String) async throws
    func sendReadReceipt(roomID: String, eventID: String) async throws
    func createDM(userID: String) async throws -> String
    func paginateBackwards(roomID: String, count: UInt) async throws
}
