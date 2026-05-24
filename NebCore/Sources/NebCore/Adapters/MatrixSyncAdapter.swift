import Foundation
import MatrixRustSDK

public final class MatrixSyncAdapter: SyncServiceProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private var syncService: MatrixRustSDK.SyncService?
    private var roomListService: RoomListService?
    private var continuation: AsyncStream<[NebRoom]>.Continuation?

    public init(clientProvider: @escaping () -> Client?) {
        self.clientProvider = clientProvider
    }

    public func startSync() async throws {
        guard let client = clientProvider() else {
            throw NebError.notLoggedIn
        }

        let sync = try await client.syncService().finish()
        let roomList = sync.roomListService()

        self.syncService = sync
        self.roomListService = roomList

        await sync.start()
    }

    public func stopSync() async throws {
        await syncService?.stop()
    }

    public func roomListStream() -> AsyncStream<[NebRoom]> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }
}

public enum NebError: Error, LocalizedError {
    case notLoggedIn
    case roomNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Not logged in"
        case .roomNotFound(let id): return "Room not found: \(id)"
        }
    }
}
