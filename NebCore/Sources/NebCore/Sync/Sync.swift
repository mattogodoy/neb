import Foundation
import MatrixRustSDK
import os

private typealias SDKRoom = MatrixRustSDK.Room
private let logger = Logger(subsystem: "com.neb.app", category: "Sync")

public final class Sync: SyncProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private let database: NebDatabase
    private var syncService: MatrixRustSDK.SyncService?
    public private(set) var roomListService: RoomListService?
    public nonisolated(unsafe) private(set) var isOnline: Bool = false
    private var statusContinuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var rooms: [SDKRoom] = []
    private var knownRoomIDs: Set<String> = []
    private var allRoomsList: RoomList?
    private var entriesListener: NebRoomListEntriesListener?
    private var entriesHandle: TaskHandle?
    private var entriesController: RoomListDynamicEntriesController?
    private var emitWorkItem: DispatchWorkItem?

    public init(clientProvider: @escaping () -> Client?, database: NebDatabase) {
        self.clientProvider = clientProvider
        self.database = database
    }

    public func start() async throws {
        guard let client = clientProvider() else {
            throw NebError.notLoggedIn
        }

        var attempt = 0
        let maxDelay: UInt64 = 30_000_000_000 // 30 seconds

        while !Task.isCancelled {
            do {
                logger.info("Starting sync (attempt \(attempt + 1))...")
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
                isOnline = true
                for (_, c) in statusContinuations { c.yield(true) }
                logger.info("Sync service started")
                return // success — exit the retry loop
            } catch {
                attempt += 1
                let delay = min(UInt64(pow(2.0, Double(min(attempt, 5)))) * 1_000_000_000, maxDelay)
                logger.warning("Sync attempt \(attempt) failed: \(error.localizedDescription), retrying in \(delay / 1_000_000_000)s")
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    public func stop() async throws {
        await syncService?.stop()
        isOnline = false
        for (_, c) in statusContinuations { c.yield(false) }
    }

    public func statusStream() -> AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { continuation in
            self.statusContinuations[id] = continuation
            continuation.onTermination = { _ in
                self.statusContinuations.removeValue(forKey: id)
            }
            continuation.yield(self.isOnline)
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

        logger.info("Room list updated: \(self.rooms.count) rooms")

        emitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.convertAndWriteToDatabase()
        }
        emitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func convertAndWriteToDatabase() {
        let snapshot = rooms
        Task {
            var currentRoomIDs: Set<String> = []
            for room in snapshot {
                let roomID = room.id()
                currentRoomIDs.insert(roomID)
                let name = room.displayName() ?? roomID

                var isDirect = false
                var unread: UInt64 = 0
                var directUserID: String? = nil
                var avatarURL: String? = nil
                var memberCount: UInt64 = 0
                do {
                    let info = try await room.roomInfo()
                    isDirect = info.isDirect
                    unread = max(info.numUnreadMessages, info.numUnreadNotifications)
                    avatarURL = info.avatarUrl
                    memberCount = info.activeMembersCount

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

                let record = RoomRecord(
                    roomID: roomID,
                    name: name,
                    avatarURL: avatarURL,
                    unreadCount: Int(unread),
                    isDirect: isDirect,
                    directUserID: directUserID,
                    memberCount: Int(memberCount)
                )
                try? database.upsertRoom(record)
            }

            // Remove rooms that are no longer in the list
            let removedIDs = self.knownRoomIDs.subtracting(currentRoomIDs)
            for roomID in removedIDs {
                try? self.database.deleteRoom(roomID: roomID)
            }
            self.knownRoomIDs = currentRoomIDs

            logger.info("Wrote \(currentRoomIDs.count) rooms to database")
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
