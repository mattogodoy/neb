import Foundation
@testable import NebCore

final class MockAuthService: AuthServiceProtocol, @unchecked Sendable {
    var loginResult: Result<Void, Error> = .success(())
    var restoreResult: Bool = false
    var currentAuthState: AuthState = .loggedOut
    private var authContinuation: AsyncStream<AuthState>.Continuation?

    func login(homeserverURL: String, username: String, password: String) async throws {
        currentAuthState = .loggingIn
        authContinuation?.yield(.loggingIn)
        try loginResult.get()
        let state = AuthState.loggedIn(userID: "@\(username):\(homeserverURL)")
        currentAuthState = state
        authContinuation?.yield(state)
    }

    func restoreSession() async throws -> Bool {
        if restoreResult {
            currentAuthState = .loggedIn(userID: "@restored:example.com")
            authContinuation?.yield(currentAuthState)
        }
        return restoreResult
    }

    func logout() async throws {
        currentAuthState = .loggedOut
        authContinuation?.yield(.loggedOut)
    }

    var authState: AuthState {
        get async { currentAuthState }
    }

    func authStateStream() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            self.authContinuation = continuation
            continuation.yield(self.currentAuthState)
        }
    }
}
