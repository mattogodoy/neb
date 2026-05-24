import Foundation

public struct VerificationEmoji: Equatable, Sendable {
    public let symbol: String
    public let description: String

    public init(symbol: String, description: String) {
        self.symbol = symbol
        self.description = description
    }
}

public enum VerificationState: Equatable, Sendable {
    case idle
    case requested
    case waitingForAcceptance
    case showingEmoji([VerificationEmoji])
    case confirmed
    case failed(String)
    case timedOut
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .confirmed, .failed, .timedOut, .cancelled:
            return true
        default:
            return false
        }
    }

    public var userAction: String? {
        switch self {
        case .idle:
            return nil
        case .requested:
            return "Accept the verification request on your other device."
        case .waitingForAcceptance:
            return "Waiting for the other side to accept..."
        case .showingEmoji:
            return "Compare the emoji below with your other device. Do they match?"
        case .confirmed:
            return "Verification complete!"
        case .failed(let reason):
            return "Verification failed: \(reason). You can try again."
        case .timedOut:
            return "Verification timed out. Please try again."
        case .cancelled:
            return "Verification was cancelled."
        }
    }
}
