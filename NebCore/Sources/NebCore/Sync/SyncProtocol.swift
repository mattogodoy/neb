import Foundation

public protocol SyncProtocol: Sendable {
    func start() async throws
    func stop() async throws
    var isOnline: Bool { get }
    func statusStream() -> AsyncStream<Bool>
}
