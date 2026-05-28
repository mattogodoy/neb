import Foundation

public protocol MembersProtocol: Sendable {
    func members(roomID: String) async throws -> [NebUser]
    func invite(roomID: String, userID: String) async throws
    func kick(roomID: String, userID: String, reason: String?) async throws
    func ban(roomID: String, userID: String, reason: String?) async throws
    func unban(roomID: String, userID: String) async throws
    func acceptInvite(roomID: String) async throws
}
