import Foundation
@testable import NebCore

final class MockSession: AuthProtocol, SessionProtocol, @unchecked Sendable {
    var loginResult: Result<Void, Error> = .success(())
    var restoreResult: Bool = false
    var currentState: AuthState = .loggedOut
    var _userID: String? = nil
    var _homeserverURL: String? = nil
    var _deviceID: String? = nil
    private var stateContinuation: AsyncStream<AuthState>.Continuation?

    // MARK: - AuthProtocol

    func login(homeserverURL: String, username: String, password: String) async throws {
        currentState = .loggingIn
        stateContinuation?.yield(.loggingIn)
        try loginResult.get()
        let userID = "@\(username):\(homeserverURL)"
        _userID = userID
        _homeserverURL = homeserverURL
        _deviceID = "MOCK_DEVICE"
        let state = AuthState.loggedIn(userID: userID)
        currentState = state
        stateContinuation?.yield(state)
    }

    func logout() async throws {
        currentState = .loggedOut
        _userID = nil
        _homeserverURL = nil
        _deviceID = nil
        stateContinuation?.yield(.loggedOut)
    }

    // MARK: - SessionProtocol

    var userID: String? {
        get async { _userID }
    }

    var homeserverURL: String? {
        get async { _homeserverURL }
    }

    var deviceID: String? {
        get async { _deviceID }
    }

    func restore() async throws -> Bool {
        if restoreResult {
            _userID = "@restored:example.com"
            _homeserverURL = "https://example.com"
            _deviceID = "MOCK_DEVICE"
            currentState = .loggedIn(userID: "@restored:example.com")
            stateContinuation?.yield(currentState)
        }
        return restoreResult
    }

    var state: AuthState {
        get async { currentState }
    }

    func stateStream() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            self.stateContinuation = continuation
            continuation.yield(self.currentState)
        }
    }
}
