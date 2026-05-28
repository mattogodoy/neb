import Foundation

public protocol PrivacyProtocol: Sendable {
    func startDeviceVerification() async throws
    func startUserVerification(userID: String) async throws
    func acceptVerification() async throws
    func confirmEmoji() async throws
    func declineEmoji() async throws
    func cancelVerification() async throws
    func verificationStateStream() -> AsyncStream<VerificationState>
    func isUserVerified(userID: String) async -> Bool
    func hasKeyBackup() async throws -> Bool
    func recoverKeys(recoveryKey: String) async throws
}
