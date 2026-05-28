import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Backfill")

public final class BackfillWorker: @unchecked Sendable {
    private let clientProvider: () -> Client?
    private let roomListServiceProvider: () -> RoomListService?
    private let database: NebDatabase
    nonisolated(unsafe) private var task: Task<Void, Never>?

    public init(
        clientProvider: @escaping () -> Client?,
        roomListServiceProvider: @escaping () -> RoomListService?,
        database: NebDatabase
    ) {
        self.clientProvider = clientProvider
        self.roomListServiceProvider = roomListServiceProvider
        self.database = database
    }

    public func start(roomIDs: [String]) {
        task?.cancel()
        task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            for roomID in roomIDs {
                guard !Task.isCancelled else { break }
                await self.backfillRoom(roomID: roomID)
            }
            logger.info("Backfill worker finished all rooms")
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func prioritize(roomID: String, allRoomIDs: [String]) {
        var reordered = [roomID]
        reordered.append(contentsOf: allRoomIDs.filter { $0 != roomID })
        start(roomIDs: reordered)
    }

    private func backfillRoom(roomID: String) async {
        do {
            if let state = try database.backfillState(roomID: roomID), state.reachedStart {
                logger.info("Backfill: \(roomID) already reached start, skipping")
                return
            }

            guard let client = clientProvider() else { return }

            if let rls = roomListServiceProvider() {
                try? await rls.subscribeToRooms(roomIds: [roomID])
            }

            guard let room = try? client.getRoom(roomId: roomID) else {
                logger.warning("Backfill: room \(roomID) not found")
                return
            }

            let timeline = try await room.timeline()
            let myUserID = (try? client.userId()) ?? ""

            let listener = BackfillTimelineListener(roomID: roomID, myUserID: myUserID, database: database)
            let listenerHandle = await timeline.addListener(listener: listener)
            // Must retain listenerHandle to prevent SDK deallocation crash
            _ = listenerHandle

            logger.info("Backfill: starting \(roomID)")

            let batchSize: UInt16 = 50
            var totalBatches = 0
            let maxBatches = 200 // Safety limit: 200 * 50 = 10,000 messages per room

            while !Task.isCancelled && totalBatches < maxBatches {
                let hitStart = try await timeline.paginateBackwards(numEvents: batchSize)
                totalBatches += 1

                if hitStart {
                    try database.updateBackfillState(BackfillState(
                        roomID: roomID, reachedStart: true
                    ))
                    logger.info("Backfill: \(roomID) reached start after \(totalBatches) batches")
                    break
                }

                try database.updateBackfillState(BackfillState(
                    roomID: roomID, reachedStart: false
                ))

                await Task.yield()
            }

            if totalBatches >= maxBatches {
                logger.info("Backfill: \(roomID) hit batch limit (\(maxBatches))")
            }
        } catch {
            logger.error("Backfill: error in \(roomID): \(error)")
        }
    }
}

// MARK: - BackfillTimelineListener

private final class BackfillTimelineListener: TimelineListener, @unchecked Sendable {
    private let roomID: String
    private let myUserID: String
    private let database: NebDatabase
    nonisolated(unsafe) private var items: [TimelineItem] = []

    init(roomID: String, myUserID: String, database: NebDatabase) {
        self.roomID = roomID
        self.myUserID = myUserID
        self.database = database
    }

    func onUpdate(diff: [TimelineDiff]) {
        for d in diff {
            switch d {
            case .append(let values):
                items.append(contentsOf: values)
            case .clear:
                items.removeAll()
            case .pushFront(let value):
                items.insert(value, at: 0)
            case .pushBack(let value):
                items.append(value)
            case .popFront:
                if !items.isEmpty { items.removeFirst() }
            case .popBack:
                if !items.isEmpty { items.removeLast() }
            case .insert(let index, let value):
                let i = Int(index)
                if i <= items.count { items.insert(value, at: i) }
            case .set(let index, let value):
                let i = Int(index)
                if i < items.count { items[i] = value }
            case .remove(let index):
                let i = Int(index)
                if i < items.count { items.remove(at: i) }
            case .truncate(let length):
                let len = Int(length)
                if len < items.count { items = Array(items.prefix(len)) }
            case .reset(let values):
                items = values
            }
        }

        for item in items {
            processItem(item)
        }
    }

    private func processItem(_ item: TimelineItem) {
        guard let event = item.asEvent() else { return }
        guard case .msgLike(let msgLike) = event.content else { return }

        let body: String
        var formattedBody: String? = nil
        var isEdited = false

        switch msgLike.kind {
        case .message(let msgContent):
            body = msgContent.body
            isEdited = msgContent.isEdited
            if case .text(let textContent) = msgContent.msgType,
               let formatted = textContent.formatted,
               case .html = formatted.format {
                formattedBody = formatted.body
            }
        case .unableToDecrypt:
            body = "\u{1F512} Encrypted message (verify this device to decrypt)"
        default:
            return
        }

        let eventID: String
        switch event.eventOrTransactionId {
        case .eventId(let id): eventID = id
        case .transactionId(let id): eventID = id
        }

        let timestamp = TimeInterval(event.timestamp) / 1000

        var senderName = event.sender
        var senderAvatarURL: String? = nil
        switch event.senderProfile {
        case .ready(let displayName, _, let avatarUrl):
            if let name = displayName { senderName = name }
            senderAvatarURL = avatarUrl
        default:
            break
        }

        let record = MessageRecord(
            eventID: eventID,
            roomID: roomID,
            senderID: event.sender,
            body: body,
            formattedBody: formattedBody,
            timestamp: timestamp,
            isEdited: isEdited,
            sendStatus: "sent"
        )
        try? database.insertMessage(record)
        try? database.upsertProfile(userID: event.sender, displayName: senderName, avatarURL: senderAvatarURL)
    }
}
