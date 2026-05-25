import Foundation

public enum DeviceVerificationStatus: Equatable, Sendable {
    case unknown
    case verified
    case unverified
}

public protocol CryptoServiceProtocol: Sendable {
    func startDeviceVerification() async throws
    func startUserVerification(userID: String) async throws
    func acceptVerification() async throws
    func confirmEmoji() async throws
    func declineEmoji() async throws
    func cancelVerification() async throws
    func verificationStateStream() -> AsyncStream<VerificationState>
    func deviceVerificationStatusStream() -> AsyncStream<DeviceVerificationStatus>
    func isUserVerified(userID: String) async -> Bool
    func hasKeyBackup() async throws -> Bool
    func recoverKeys(recoveryKey: String) async throws
}
