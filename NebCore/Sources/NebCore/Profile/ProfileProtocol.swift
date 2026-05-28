import Foundation

public protocol ProfileProtocol: Sendable {
    func displayName() async throws -> String?
    func avatarURL() async throws -> String?
    func setDisplayName(_ name: String) async throws
    func uploadAvatar(data: Data, mimeType: String) async throws
    func removeAvatar() async throws
}
