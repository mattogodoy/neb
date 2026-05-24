import Foundation

public protocol SyncServiceProtocol: Sendable {
    func startSync() async throws
    func stopSync() async throws
    func roomListStream() -> AsyncStream<[NebRoom]>
}
