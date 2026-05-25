import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Crypto")

public final class MatrixCryptoAdapter: CryptoServiceProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private var controller: SessionVerificationController?
    private var delegate: VerificationDelegate?
    private var continuation: AsyncStream<VerificationState>.Continuation?
    private var pendingRequest: SessionVerificationRequestDetails?
    private var verificationStateHandle: TaskHandle?
    private var deviceVerificationListener: DeviceVerificationStateListener?

    public init(clientProvider: @escaping () -> Client?) {
        self.clientProvider = clientProvider
    }

    public func setupVerificationListener() async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let ctrl = try await client.getSessionVerificationController()
        self.controller = ctrl

        let del = VerificationDelegate { [weak self] state in
            logger.info("Verification state: \(String(describing: state))")
            self?.continuation?.yield(state)
        } onRequest: { [weak self] details in
            logger.info("Incoming verification request from \(details.senderProfile.userId)")
            self?.pendingRequest = details
            self?.continuation?.yield(.requested)
        }
        del.controller = ctrl
        self.delegate = del
        ctrl.setDelegate(delegate: del)
        logger.info("Verification listener active")
    }

    public func startDeviceVerification() async throws {
        guard let controller else {
            try await setupVerificationListener()
            guard let controller = self.controller else { throw NebError.notLoggedIn }
            try await controller.requestDeviceVerification()
            continuation?.yield(.waitingForAcceptance)
            return
        }
        try await controller.requestDeviceVerification()
        continuation?.yield(.waitingForAcceptance)
    }

    public func startUserVerification(userID: String) async throws {
        guard let controller else {
            logger.error("startUserVerification: no controller, setting up listener first")
            try await setupVerificationListener()
            guard let controller = self.controller else { throw NebError.notLoggedIn }
            logger.info("startUserVerification: requesting verification for \(userID)")
            try await controller.requestUserVerification(userId: userID)
            continuation?.yield(.waitingForAcceptance)
            return
        }
        logger.info("startUserVerification: requesting verification for \(userID)")
        try await controller.requestUserVerification(userId: userID)
        continuation?.yield(.waitingForAcceptance)
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
            self.continuation = continuation
            continuation.yield(.idle)
        }
    }

    public func deviceVerificationStatusStream() -> AsyncStream<DeviceVerificationStatus> {
        AsyncStream { continuation in
            guard let client = clientProvider() else {
                continuation.yield(.unknown)
                return
            }
            let encryption = client.encryption()
            let initial = encryption.verificationState()
            continuation.yield(Self.mapVerificationState(initial))

            let listener = DeviceVerificationStateListener { state in
                continuation.yield(Self.mapVerificationState(state))
            }
            self.verificationStateHandle = encryption.verificationStateListener(listener: listener)
            self.deviceVerificationListener = listener
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

    public func hasKeyBackup() async throws -> Bool {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        return try await client.encryption().backupExistsOnServer()
    }

    public func recoverKeys(recoveryKey: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let encryption = client.encryption()
        logger.info("Starting key recovery...")
        try await encryption.recover(recoveryKey: recoveryKey)
        logger.info("Key recovery complete, waiting for E2EE initialization...")
        await encryption.waitForE2eeInitializationTasks()
        logger.info("E2EE initialization complete")
    }

    private static func mapVerificationState(_ state: MatrixRustSDK.VerificationState) -> DeviceVerificationStatus {
        switch state {
        case .verified: return .verified
        case .unverified: return .unverified
        case .unknown: return .unknown
        }
    }
}

private final class VerificationDelegate: SessionVerificationControllerDelegate, @unchecked Sendable {
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
        logger.info("Other side accepted, starting SAS verification")
        Task {
            try? await controller?.startSasVerification()
        }
    }

    func didStartSasVerification() {
        // Emoji data will follow in didReceiveVerificationData
    }

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

    func didFail() {
        onStateChange(.failed("Verification failed"))
    }

    func didCancel() {
        onStateChange(.cancelled)
    }

    func didFinish() {
        onStateChange(.confirmed)
    }
}

private final class DeviceVerificationStateListener: MatrixRustSDK.VerificationStateListener, @unchecked Sendable {
    private let handler: (MatrixRustSDK.VerificationState) -> Void

    init(handler: @escaping (MatrixRustSDK.VerificationState) -> Void) {
        self.handler = handler
    }

    func onUpdate(status: MatrixRustSDK.VerificationState) {
        handler(status)
    }
}
