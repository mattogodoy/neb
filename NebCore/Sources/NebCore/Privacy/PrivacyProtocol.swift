import Foundation

public protocol PrivacyProtocol: Sendable {
    func blockUser(userID: String) async throws
    func unblockUser(userID: String) async throws
    func blockedUsers() async throws -> [String]
}
