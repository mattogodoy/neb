import Foundation
@testable import NebCore

final class MockCryptoService: CryptoProtocol, @unchecked Sendable {
    var currentState: VerificationState = .idle
    private var stateContinuation: AsyncStream<VerificationState>.Continuation?

    func startDeviceVerification() async throws {
        emitState(.waitingForAcceptance)
    }

    func startUserVerification(userID: String) async throws {
        emitState(.waitingForAcceptance)
    }

    func acceptVerification() async throws {
        emitState(.showingEmoji([
            VerificationEmoji(symbol: "🐶", description: "Dog"),
            VerificationEmoji(symbol: "🔒", description: "Lock"),
            VerificationEmoji(symbol: "🎵", description: "Music"),
            VerificationEmoji(symbol: "📎", description: "Paperclip"),
            VerificationEmoji(symbol: "🚀", description: "Rocket"),
            VerificationEmoji(symbol: "☎️", description: "Phone"),
            VerificationEmoji(symbol: "🏁", description: "Flag"),
        ]))
    }

    func confirmEmoji() async throws {
        emitState(.confirmed)
    }

    func declineEmoji() async throws {
        emitState(.failed("Emoji mismatch"))
    }

    func cancelVerification() async throws {
        emitState(.cancelled)
    }

    func verificationStateStream() -> AsyncStream<VerificationState> {
        AsyncStream { continuation in
            self.stateContinuation = continuation
            continuation.yield(self.currentState)
        }
    }

    func deviceVerificationStatusStream() -> AsyncStream<DeviceVerificationStatus> {
        AsyncStream { continuation in
            continuation.yield(.unverified)
        }
    }

    func isUserVerified(userID: String) async -> Bool { false }
    func hasKeyBackup() async throws -> Bool { true }
    func recoverKeys(recoveryKey: String) async throws {}

    func emitState(_ state: VerificationState) {
        currentState = state
        stateContinuation?.yield(state)
    }
}
