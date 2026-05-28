import Foundation

public protocol TimelineProtocol: Sendable {
    func messageStream(roomID: String) -> AsyncStream<[NebMessage]>
    func send(roomID: String, body: String) async throws
    func sendReply(roomID: String, body: String, replyToEventID: String) async throws
    func edit(roomID: String, eventID: String, newBody: String) async throws
    func delete(roomID: String, eventID: String, reason: String?) async throws
    func react(roomID: String, eventID: String, emoji: String) async throws
    func paginateBackwards(roomID: String, count: UInt) async throws
    func markAsRead(roomID: String) async throws
    func sendImage(roomID: String, url: URL, caption: String?) async throws
    func sendFile(roomID: String, url: URL, caption: String?) async throws
    func sendVideo(roomID: String, url: URL, thumbnailURL: URL, caption: String?) async throws
}
