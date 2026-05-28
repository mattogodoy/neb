import NebCore
import Foundation

@MainActor
@Observable
public final class VerificationViewModel {
    public private(set) var state: VerificationState = .idle
    public var errorMessage: String?

    private let securityService: any SecurityProtocol
    @ObservationIgnored nonisolated(unsafe) private var stateTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var timeoutTask: Task<Void, Never>?

    private static let timeoutSeconds: UInt64 = 60

    public init(securityService: any SecurityProtocol) {
        self.securityService = securityService
        startObserving()
    }

    deinit {
        stateTask?.cancel()
        timeoutTask?.cancel()
    }

    public func startDeviceVerification() async {
        do {
            try await securityService.startDeviceVerification()
            startTimeout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func startUserVerification(userID: String) async {
        do {
            try await securityService.startUserVerification(userID: userID)
            startTimeout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func acceptVerification() async {
        do {
            try await securityService.acceptVerification()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func confirmEmoji() async {
        do {
            try await securityService.confirmEmoji()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func declineEmoji() async {
        do {
            try await securityService.declineEmoji()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func cancelVerification() async {
        do {
            try await securityService.cancelVerification()
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
            for await newState in self.securityService.verificationStateStream() {
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
