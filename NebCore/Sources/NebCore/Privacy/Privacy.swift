import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Privacy")

public final class Privacy: PrivacyProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?

    public init(clientProvider: @escaping () -> Client?) {
        self.clientProvider = clientProvider
    }

    public func blockUser(userID: String) async throws {
        guard let client = clientProvider() else { return }
        try await client.ignoreUser(userId: userID)
        logger.info("Blocked user \(userID)")
    }

    public func unblockUser(userID: String) async throws {
        guard let client = clientProvider() else { return }
        try await client.unignoreUser(userId: userID)
        logger.info("Unblocked user \(userID)")
    }

    public func blockedUsers() async throws -> [String] {
        guard let client = clientProvider() else { return [] }
        return try await client.ignoredUsers()
    }
}
