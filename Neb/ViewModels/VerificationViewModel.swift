import NebCore
import Foundation

@MainActor
@Observable
public final class VerificationViewModel {
    public private(set) var state: VerificationState = .idle
    public var errorMessage: String?

    private let privacyService: any PrivacyProtocol
    @ObservationIgnored nonisolated(unsafe) private var stateTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var timeoutTask: Task<Void, Never>?

    private static let timeoutSeconds: UInt64 = 60

    public init(privacyService: any PrivacyProtocol) {
        self.privacyService = privacyService
        startObserving()
    }

    deinit {
        stateTask?.cancel()
        timeoutTask?.cancel()
    }

    public func startDeviceVerification() async {
        do {
            try await privacyService.startDeviceVerification()
            startTimeout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func startUserVerification(userID: String) async {
        do {
            try await privacyService.startUserVerification(userID: userID)
            startTimeout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func acceptVerification() async {
        do {
            try await privacyService.acceptVerification()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func confirmEmoji() async {
        do {
            try await privacyService.confirmEmoji()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func declineEmoji() async {
        do {
            try await privacyService.declineEmoji()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func cancelVerification() async {
        do {
            try await privacyService.cancelVerification()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func reset() {
        state = .idle
        errorMessage = nil
        timeoutTask?.cancel()
    }

    private func startObserving() {
        stateTask = Task { [weak self] in
            guard let self else { return }
            for await newState in self.privacyService.verificationStateStream() {
                guard !Task.isCancelled else { break }
                self.state = newState
                if newState.isTerminal {
                    self.timeoutTask?.cancel()
                }
            }
        }
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if !self.state.isTerminal {
                self.state = .timedOut
            }
        }
    }
}
