import Foundation

public protocol SessionProtocol: Sendable {
    var userID: String? { get async }
    var homeserverURL: String? { get async }
    var deviceID: String? { get async }
    func restore() async throws -> Bool
    var state: AuthState { get async }
    func stateStream() -> AsyncStream<AuthState>
}
