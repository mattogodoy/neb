import Foundation

public enum AuthState: Equatable, Sendable {
    case loggedOut
    case loggingIn
    case loggedIn(userID: String)
    case failed(String)
}

public protocol AuthProtocol: Sendable {
    func login(homeserverURL: String, username: String, password: String) async throws
    func logout() async throws
}
