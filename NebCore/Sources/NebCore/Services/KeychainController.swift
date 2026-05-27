import Foundation
import Security
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Keychain")

public final class KeychainController: Sendable {
    private let service: String

    public init(service: String = "com.neb.app") {
        self.service = service
    }

    // MARK: - Session

    public func saveSession(_ session: NebSession, for userID: String) throws {
        let data = try JSONEncoder().encode(session)
        try save(data: data, account: userID)
    }

    public func loadSession(for userID: String) -> NebSession? {
        guard let data = load(account: userID) else { return nil }
        return try? JSONDecoder().decode(NebSession.self, from: data)
    }

    // MARK: - Passphrase

    public func savePassphrase(_ passphrase: String, for userID: String) throws {
        guard let data = passphrase.data(using: .utf8) else { return }
        try save(data: data, account: userID + ".passphrase")
    }

    public func loadPassphrase(for userID: String) -> String? {
        guard let data = load(account: userID + ".passphrase") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    public func deleteAll(for userID: String) {
        delete(account: userID)
        delete(account: userID + ".passphrase")
    }

    // MARK: - Private

    private func save(data: Data, account: String) throws {
        // Delete existing item first to avoid duplicates
        // Delete existing item first to avoid duplicates
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain save failed for \(account) service=\(self.service): \(status)")
            throw KeychainError.saveFailed(status)
        }
    }



    private func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                logger.error("Keychain load failed for \(account): \(status)")
            }
            return nil
        }

        return result as? Data
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum KeychainError: Error {
    case saveFailed(OSStatus)
}
