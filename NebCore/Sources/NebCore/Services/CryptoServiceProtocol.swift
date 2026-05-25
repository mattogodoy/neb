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
    func recoveryKey() async throws -> String?
}
