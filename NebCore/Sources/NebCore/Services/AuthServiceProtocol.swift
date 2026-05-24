import Foundation

public enum AuthState: Equatable, Sendable {
    case loggedOut
    case loggingIn
    case loggedIn(userID: String)
    case failed(String)
}

public protocol AuthServiceProtocol: Sendable {
    func login(homeserverURL: String, username: String, password: String) async throws
    func restoreSession() async throws -> Bool
    func logout() async throws
    var authState: AuthState { get async }
    func authStateStream() -> AsyncStream<AuthState>
}
