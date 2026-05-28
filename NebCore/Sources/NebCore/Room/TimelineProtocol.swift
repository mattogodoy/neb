import Foundation

public protocol TimelineProtocol: Sendable {
    /// Start syncing a room's timeline to the database.
    func startTimelineSync(roomID: String) async throws
    /// Stop syncing a room's timeline.
    func stopTimelineSync(roomID: String) async throws
    /// Send a message (writes pending row to DB, forwards to SDK).
    func send(roomID: String, body: String) async throws
    func sendReply(roomID: String, body: String, replyToEventID: String) async throws
    func edit(roomID: String, eventID: String, newBody: String) async throws
    func delete(roomID: String, eventID: String, reason: String?) async throws
    func react(roomID: String, eventID: String, emoji: String) async throws
    func markAsRead(roomID: String) async throws
    func sendImage(roomID: String, url: URL, caption: String?) async throws
    func sendFile(roomID: String, url: URL, caption: String?) async throws
    func sendVideo(roomID: String, url: URL, thumbnailURL: URL, caption: String?) async throws
}
