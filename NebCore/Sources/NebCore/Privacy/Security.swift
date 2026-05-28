import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Security")

public final class Security: SecurityProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private var controller: SessionVerificationController?
    private var delegate: VerificationDelegateImpl?
    private var verificationContinuation: AsyncStream<VerificationState>.Continuation?
    private var pendingRequest: SessionVerificationRequestDetails?
    private var backupStateHandle: TaskHandle?
    private var backupStateListenerImpl: BackupStateListenerImpl?
    private var recoveryStateHandle: TaskHandle?
    private var recoveryStateListenerImpl: RecoveryStateListenerImpl?

    public init(clientProvider: @escaping () -> Client?) {
        self.clientProvider = clientProvider
    }

    public func setupVerificationListener() async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let ctrl = try await client.getSessionVerificationController()
        self.controller = ctrl

        let del = VerificationDelegateImpl { [weak self] state in
            logger.info("Verification state: \(String(describing: state))")
            self?.verificationContinuation?.yield(state)
        } onRequest: { [weak self] details in
            logger.info("Incoming verification request from \(details.senderProfile.userId)")
            self?.pendingRequest = details
            self?.verificationContinuation?.yield(.requested)
        }
        del.controller = ctrl
        self.delegate = del
        ctrl.setDelegate(delegate: del)
        logger.info("Verification listener active")
    }

    // MARK: - Verification flows

    public func startDeviceVerification() async throws {
        guard let controller else {
            try await setupVerificationListener()
            guard let controller = self.controller else { throw NebError.notLoggedIn }
            try await controller.requestDeviceVerification()
            verificationContinuation?.yield(.waitingForAcceptance)
            return
        }
        try await controller.requestDeviceVerification()
        verificationContinuation?.yield(.waitingForAcceptance)
    }

    public func startUserVerification(userID: String) async throws {
        guard let controller else {
            try await setupVerificationListener()
            guard let controller = self.controller else { throw NebError.notLoggedIn }
            try await controller.requestUserVerification(userId: userID)
            verificationContinuation?.yield(.waitingForAcceptance)
            return
        }
        try await controller.requestUserVerification(userId: userID)
        verificationContinuation?.yield(.waitingForAcceptance)
    }

    public func acceptVerification() async throws {
        guard let controller else { return }
        if let request = pendingRequest {
            try await controller.acknowledgeVerificationRequest(
                senderId: request.senderProfile.userId,
                flowId: request.flowId
            )
            try await controller.acceptVerificationRequest()
            try await controller.startSasVerification()
            pendingRequest = nil
        } else {
            try await controller.startSasVerification()
        }
    }

    public func confirmEmoji() async throws {
        try await controller?.approveVerification()
    }

    public func declineEmoji() async throws {
        try await controller?.declineVerification()
    }

    public func cancelVerification() async throws {
        try await controller?.cancelVerification()
    }

    public func verificationStateStream() -> AsyncStream<VerificationState> {
        AsyncStream { continuation in
            self.verificationContinuation = continuation
            continuation.yield(.idle)
        }
    }

    public func isUserVerified(userID: String) async -> Bool {
        guard let client = clientProvider() else { return false }
        do {
            let identity = try await client.encryption().userIdentity(userId: userID, fallbackToServer: false)
            return identity?.isVerified() ?? false
        } catch {
            return false
        }
    }

    // MARK: - Key backup

    public func hasKeyBackup() async throws -> Bool {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        return try await client.encryption().backupExistsOnServer()
    }

    public func enableBackups() async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        try await client.encryption().enableBackups()
        logger.info("Key backups enabled")
    }

    public func disableRecovery() async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        try await client.encryption().disableRecovery()
        logger.info("Recovery disabled")
    }

    public func backupStateStream() -> AsyncStream<BackupState> {
        AsyncStream { continuation in
            guard let client = clientProvider() else {
                continuation.yield(.unknown)
                return
            }
            let encryption = client.encryption()
            continuation.yield(Self.mapBackupState(encryption.backupState()))

            let listener = BackupStateListenerImpl { state in
                continuation.yield(Self.mapBackupState(state))
            }
            self.backupStateHandle = encryption.backupStateListener(listener: listener)
            self.backupStateListenerImpl = listener
        }
    }

    // MARK: - Recovery

    public func recoverKeys(recoveryKey: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let encryption = client.encryption()
        logger.info("Starting key recovery...")
        do {
            try await encryption.recoverAndFixBackup(recoveryKey: recoveryKey)
        } catch let error as RecoveryError {
            logger.error("Key recovery failed: \(error)")
            switch error {
            case .SecretStorage:
                throw NebError.recoveryFailed("Could not find secret storage data on the server. You may need to reset your recovery key from another client.")
            case .Import:
                throw NebError.recoveryFailed("Invalid recovery key. Please check and try again.")
            case .BackupExistsOnServer:
                throw NebError.recoveryFailed("A key backup conflict was detected. Try disabling and re-enabling recovery from another client.")
            case .Client:
                throw NebError.recoveryFailed("Could not connect to the server. Check your connection and try again.")
            }
        }
        logger.info("Key recovery complete, waiting for E2EE initialization...")
        await encryption.waitForE2eeInitializationTasks()
        logger.info("E2EE initialization complete")
    }

    public func generateRecoveryKey(passphrase: String?) async throws -> String {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let listener = NoOpRecoveryProgressListener()
        let key = try await client.encryption().enableRecovery(
            waitForBackupsToUpload: true,
            passphrase: passphrase,
            progressListener: listener
        )
        logger.info("Recovery key generated")
        return key
    }

    public func resetRecoveryKey() async throws -> String {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let key = try await client.encryption().resetRecoveryKey()
        logger.info("Recovery key reset")
        return key
    }

    public func recoveryStateStream() -> AsyncStream<RecoveryState> {
        AsyncStream { continuation in
            guard let client = clientProvider() else {
                continuation.yield(.unknown)
                return
            }
            let encryption = client.encryption()
            continuation.yield(Self.mapRecoveryState(encryption.recoveryState()))

            let listener = RecoveryStateListenerImpl { state in
                continuation.yield(Self.mapRecoveryState(state))
            }
            self.recoveryStateHandle = encryption.recoveryStateListener(listener: listener)
            self.recoveryStateListenerImpl = listener
        }
    }

    // MARK: - Identity

    public func resetIdentity() async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let _ = try await client.encryption().resetIdentity()
        logger.info("Identity reset")
    }

    public func crossSigningResetURL() async -> URL? {
        guard let client = clientProvider() else { return nil }
        guard let urlString = try? await client.accountUrl(action: .crossSigningReset) else { return nil }
        return URL(string: urlString)
    }

    // MARK: - Private

    private static func mapBackupState(_ state: MatrixRustSDK.BackupState) -> BackupState {
        switch state {
        case .unknown: return .unknown
        case .creating: return .creating
        case .enabling: return .enabling
        case .resuming: return .resuming
        case .enabled: return .enabled
        case .downloading: return .downloading
        case .disabling: return .disabling
        }
    }

    private static func mapRecoveryState(_ state: MatrixRustSDK.RecoveryState) -> RecoveryState {
        switch state {
        case .unknown: return .unknown
        case .enabled: return .enabled
        case .disabled: return .disabled
        case .incomplete: return .incomplete
        }
    }
}

// MARK: - SDK Listeners

private final class VerificationDelegateImpl: SessionVerificationControllerDelegate, @unchecked Sendable {
    private let onStateChange: (VerificationState) -> Void
    private let onRequest: (SessionVerificationRequestDetails) -> Void
    weak var controller: SessionVerificationController?

    init(
        onStateChange: @escaping (VerificationState) -> Void,
        onRequest: @escaping (SessionVerificationRequestDetails) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onRequest = onRequest
    }

    func didReceiveVerificationRequest(details: SessionVerificationRequestDetails) {
        onRequest(details)
    }

    func didAcceptVerificationRequest() {
        Task {
            do {
                try await controller?.startSasVerification()
            } catch {
                logger.error("Failed to start SAS verification: \(error)")
            }
        }
    }

    func didStartSasVerification() {}

    func didReceiveVerificationData(data: SessionVerificationData) {
        switch data {
        case .emojis(let emojis, _):
            let mapped = emojis.map {
                VerificationEmoji(symbol: $0.symbol(), description: $0.description())
            }
            onStateChange(.showingEmoji(mapped))
        case .decimals(let values):
            let desc = values.map { String($0) }.joined(separator: " ")
            onStateChange(.showingEmoji([VerificationEmoji(symbol: desc, description: "Decimal verification")]))
        }
    }

    func didFail() { onStateChange(.failed("Verification failed")) }
    func didCancel() { onStateChange(.cancelled) }
    func didFinish() { onStateChange(.confirmed) }
}

private final class BackupStateListenerImpl: MatrixRustSDK.BackupStateListener, @unchecked Sendable {
    private let handler: (MatrixRustSDK.BackupState) -> Void
    init(handler: @escaping (MatrixRustSDK.BackupState) -> Void) { self.handler = handler }
    func onUpdate(status: MatrixRustSDK.BackupState) { handler(status) }
}

private final class RecoveryStateListenerImpl: MatrixRustSDK.RecoveryStateListener, @unchecked Sendable {
    private let handler: (MatrixRustSDK.RecoveryState) -> Void
    init(handler: @escaping (MatrixRustSDK.RecoveryState) -> Void) { self.handler = handler }
    func onUpdate(status: MatrixRustSDK.RecoveryState) { handler(status) }
}

private final class NoOpRecoveryProgressListener: EnableRecoveryProgressListener, @unchecked Sendable {
    func onUpdate(status: EnableRecoveryProgress) {}
}
