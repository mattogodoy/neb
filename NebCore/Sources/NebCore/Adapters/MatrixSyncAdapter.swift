import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Sync")

public final class MatrixSyncAdapter: SyncServiceProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private var syncService: MatrixRustSDK.SyncService?
    public private(set) var roomListService: RoomListService?
    private var continuations: [UUID: AsyncStream<[NebRoom]>.Continuation] = [:]
    private var rooms: [Room] = []
    private var allRoomsList: RoomList?
    private var entriesListener: NebRoomListEntriesListener?
    private var entriesHandle: TaskHandle?
    private var entriesController: RoomListDynamicEntriesController?
    private var latestNebRooms: [NebRoom] = []
    private var emitWorkItem: DispatchWorkItem?

    public init(clientProvider: @escaping () -> Client?) {
        self.clientProvider = clientProvider
    }

    public func startSync() async throws {
        guard let client = clientProvider() else {
            throw NebError.notLoggedIn
        }

        logger.info("Starting sync...")
        let sync = try await client.syncService().finish()
        let roomList = sync.roomListService()

        self.syncService = sync
        self.roomListService = roomList

        let allRooms = try await roomList.allRooms()
        self.allRoomsList = allRooms

        let listener = NebRoomListEntriesListener { [weak self] updates in
            self?.applyUpdates(updates)
        }
        self.entriesListener = listener

        let result = allRooms.entriesWithDynamicAdapters(
            pageSize: 100,
            listener: listener
        )
        self.entriesHandle = result.entriesStream()
        self.entriesController = result.controller()
        let _ = self.entriesController?.setFilter(kind: .all(filters: []))

        logger.info("Sync service starting...")
        await sync.start()
        logger.info("Sync service started")
    }

    public func stopSync() async throws {
        await syncService?.stop()
    }

    public func roomListStream() -> AsyncStream<[NebRoom]> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { _ in
                self.continuations.removeValue(forKey: id)
            }
            if !self.latestNebRooms.isEmpty {
                continuation.yield(self.latestNebRooms)
            }
        }
    }

    private func applyUpdates(_ updates: [RoomListEntriesUpdate]) {
        for update in updates {
            switch update {
            case .append(let values):
                rooms.append(contentsOf: values)
            case .clear:
                rooms.removeAll()
            case .pushFront(let value):
                rooms.insert(value, at: 0)
            case .pushBack(let value):
                rooms.append(value)
            case .popFront:
                if !rooms.isEmpty { rooms.removeFirst() }
            case .popBack:
                if !rooms.isEmpty { rooms.removeLast() }
            case .insert(let index, let value):
                let i = Int(index)
                if i <= rooms.count { rooms.insert(value, at: i) }
            case .set(let index, let value):
                let i = Int(index)
                if i < rooms.count { rooms[i] = value }
            case .remove(let index):
                let i = Int(index)
                if i < rooms.count { rooms.remove(at: i) }
            case .truncate(let length):
                let len = Int(length)
                if len < rooms.count { rooms = Array(rooms.prefix(len)) }
            case .reset(let values):
                rooms = values
            }
        }

        if self.rooms.count != self.latestNebRooms.count {
            logger.info("Room list updated: \(self.rooms.count) rooms")
        }

        emitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.convertAndEmit()
        }
        emitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func convertAndEmit() {
        let snapshot = rooms
        Task {
            var nebRooms: [NebRoom] = []
            for room in snapshot {
                let roomID = room.id()
                let name = room.displayName() ?? roomID

                var isDirect = false
                var unread: UInt64 = 0
                var directUserID: String? = nil
                var avatarURL: String? = nil
                do {
                    let info = try await room.roomInfo()
                    isDirect = info.isDirect
                    unread = max(info.numUnreadMessages, info.numUnreadNotifications)
                    avatarURL = info.avatarUrl

                    if isDirect {
                        let myUserID = try? self.clientProvider()?.userId()
                        let members = try await room.membersNoSync()
                        while let chunk = members.nextChunk(chunkSize: 10) {
                            for member in chunk {
                                if member.userId != myUserID && member.membership == .join {
                                    directUserID = member.userId
                                    if avatarURL == nil {
                                        avatarURL = member.avatarUrl
                                    }
                                    break
                                }
                            }
                            if directUserID != nil { break }
                        }
                    }
                } catch {
                    logger.warning("Failed to get room info for \(roomID): \(error.localizedDescription)")
                }

                nebRooms.append(NebRoom(
                    id: roomID,
                    name: name,
                    avatarURL: avatarURL,
                    lastMessage: nil,
                    lastMessageTimestamp: nil,
                    unreadCount: UInt(unread),
                    isDirect: isDirect,
                    directUserID: directUserID,
                    memberCount: 0
                ))
            }

            logger.info("Emitting \(nebRooms.count) rooms to \(self.continuations.count) listeners")
            self.latestNebRooms = nebRooms
            for (_, continuation) in self.continuations {
                continuation.yield(nebRooms)
            }
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

private final class NebRoomListEntriesListener: RoomListEntriesListener, @unchecked Sendable {
    private let handler: @Sendable ([RoomListEntriesUpdate]) -> Void

    init(handler: @escaping @Sendable ([RoomListEntriesUpdate]) -> Void) {
        self.handler = handler
    }

    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        handler(roomEntriesUpdate)
    }
}
