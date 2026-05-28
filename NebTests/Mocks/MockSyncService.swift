import Foundation
import NebCore

final class MockSyncService: SyncProtocol, @unchecked Sendable {
    var isOnline: Bool = false
    var started = false
    var stopped = false

    func start() async throws {
        started = true
        isOnline = true
    }

    func stop() async throws {
        stopped = true
        isOnline = false
    }

    func statusStream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.yield(self.isOnline)
        }
    }
}
