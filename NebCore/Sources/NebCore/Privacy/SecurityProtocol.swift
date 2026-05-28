import Foundation

public enum BackupState: Equatable, Sendable {
    case unknown
    case creating
    case enabling
    case resuming
    case enabled
    case downloading
    case disabling
}

public enum RecoveryState: Equatable, Sendable {
    case unknown
    case enabled
    case disabled
    case incomplete
}

public protocol SecurityProtocol: Sendable {
    // Verification flows
    func startDeviceVerification() async throws
    func startUserVerification(userID: String) async throws
    func acceptVerification() async throws
    func confirmEmoji() async throws
    func declineEmoji() async throws
    func cancelVerification() async throws
    func verificationStateStream() -> AsyncStream<VerificationState>
    func isUserVerified(userID: String) async -> Bool

    // Key backup
    func hasKeyBackup() async throws -> Bool
    func enableBackups() async throws
    func disableRecovery() async throws
    func backupStateStream() -> AsyncStream<BackupState>

    // Recovery
    func recoverKeys(recoveryKey: String) async throws
    func generateRecoveryKey(passphrase: String?) async throws -> String
    func resetRecoveryKey() async throws -> String
    func recoveryStateStream() -> AsyncStream<RecoveryState>

    // Identity
    func resetIdentity() async throws
    func crossSigningResetURL() async -> URL?
}
