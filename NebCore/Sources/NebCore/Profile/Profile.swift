import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Profile")

public final class Profile: ProfileProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?

    public init(clientProvider: @escaping () -> Client?) {
        self.clientProvider = clientProvider
    }

    public func displayName() async throws -> String? {
        guard let client = clientProvider() else { return nil }
        return try await client.displayName()
    }

    public func avatarURL() async throws -> String? {
        guard let client = clientProvider() else { return nil }
        return try await client.avatarUrl()
    }

    public func setDisplayName(_ name: String) async throws {
        guard let client = clientProvider() else { return }
        try await client.setDisplayName(name: name)
        logger.info("Display name updated to \(name)")
    }

    public func uploadAvatar(data: Data, mimeType: String) async throws {
        guard let client = clientProvider() else { return }
        try await client.uploadAvatar(mimeType: mimeType, data: data)
        logger.info("Avatar uploaded (\(data.count) bytes, \(mimeType))")
    }

    public func removeAvatar() async throws {
        guard let client = clientProvider() else { return }
        try await client.removeAvatar()
        logger.info("Avatar removed")
    }
}
