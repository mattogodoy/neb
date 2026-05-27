import NebCore
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

    private let auth: any AuthProtocol
    private let session: any SessionProtocol

    public var canLogin: Bool {
        !homeserver.isEmpty && !username.isEmpty && !password.isEmpty && !isLoading
    }

    public init(auth: any AuthProtocol, session: any SessionProtocol) {
        self.auth = auth
        self.session = session
    }

    public func setHomeserver(_ value: String) { homeserver = value }
    public func setUsername(_ value: String) { username = value }
    public func setPassword(_ value: String) { password = value }

    public func login() async {
        isLoading = true
        errorMessage = nil
        do {
            try await auth.login(
                homeserverURL: homeserver,
                username: username,
                password: password
            )
            authState = await session.state
        } catch {
            errorMessage = error.localizedDescription
            authState = .failed(error.localizedDescription)
        }
        isLoading = false
    }

    public func tryRestoreSession() async -> Bool {
        do {
            let restored = try await session.restore()
            if restored {
                authState = await session.state
            }
            return restored
        } catch {
            return false
        }
    }

    public func logout() async {
        do {
            try await auth.logout()
            authState = .loggedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
