import Foundation

@MainActor
@Observable
public final class LoginViewModel {
    public var homeserver: String = ""
    public var username: String = ""
    public var password: String = ""
    public var isLoading: Bool = false
    public var errorMessage: String?
    public private(set) var authState: AuthState = .loggedOut

    private let authService: any AuthProtocol

    public var canLogin: Bool {
        !homeserver.isEmpty && !username.isEmpty && !password.isEmpty && !isLoading
    }

    public init(authService: any AuthProtocol) {
        self.authService = authService
    }

    public func setHomeserver(_ value: String) { homeserver = value }
    public func setUsername(_ value: String) { username = value }
    public func setPassword(_ value: String) { password = value }

    public func login() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.login(
                homeserverURL: homeserver,
                username: username,
                password: password
            )
            authState = await authService.authState
        } catch {
            errorMessage = error.localizedDescription
            authState = .failed(error.localizedDescription)
        }
        isLoading = false
    }

    public func tryRestoreSession() async -> Bool {
        do {
            let restored = try await authService.restoreSession()
            if restored {
                authState = await authService.authState
            }
            return restored
        } catch {
            return false
        }
    }

    public func logout() async {
        do {
            try await authService.logout()
            authState = .loggedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
