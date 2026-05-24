import Foundation
import MatrixRustSDK

public final class MatrixCryptoAdapter: CryptoServiceProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private var verificationController: SessionVerificationController?
    private var continuation: AsyncStream<VerificationState>.Continuation?

    public init(clientProvider: @escaping () -> Client?) {
        self.clientProvider = clientProvider
    }

    public func startDeviceVerification() async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let controller = try await client.getSessionVerificationController()
        self.verificationController = controller
        try await controller.startSasVerification()
        continuation?.yield(.waitingForAcceptance)
    }

    public func startUserVerification(userID: String) async throws {
        continuation?.yield(.waitingForAcceptance)
    }

    public func acceptVerification() async throws {
        try await verificationController?.approveVerification()
    }

    public func confirmEmoji() async throws {
        try await verificationController?.approveVerification()
    }

    public func declineEmoji() async throws {
        try await verificationController?.declineVerification()
    }

    public func cancelVerification() async throws {
        try await verificationController?.cancelVerification()
    }

    public func verificationStateStream() -> AsyncStream<VerificationState> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(.idle)
        }
    }

    public func recoveryKey() async throws -> String? {
        return nil
    }
}
