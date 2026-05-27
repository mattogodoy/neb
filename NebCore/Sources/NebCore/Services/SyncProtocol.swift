import Foundation

public protocol SyncProtocol: Sendable {
    func startSync() async throws
    func stopSync() async throws
    func roomListStream() -> AsyncStream<[NebRoom]>
}
