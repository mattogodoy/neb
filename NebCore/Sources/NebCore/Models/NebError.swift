import Foundation

public enum NebError: Error, LocalizedError {
    case notLoggedIn
    case roomNotFound(String)
    case recoveryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Not logged in"
        case .roomNotFound(let id): return "Room not found: \(id)"
        case .recoveryFailed(let message): return message
        }
    }
}
