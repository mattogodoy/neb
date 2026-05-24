import Foundation
@testable import NebCore

final class MockSyncService: SyncServiceProtocol, @unchecked Sendable {
    var rooms: [NebRoom] = []
    private var roomsContinuation: AsyncStream<[NebRoom]>.Continuation?

    func startSync() async throws {}
    func stopSync() async throws {}

    func roomListStream() -> AsyncStream<[NebRoom]> {
        AsyncStream { continuation in
            self.roomsContinuation = continuation
            continuation.yield(self.rooms)
        }
    }

    func emitRooms(_ rooms: [NebRoom]) {
        self.rooms = rooms
        roomsContinuation?.yield(rooms)
    }
}
