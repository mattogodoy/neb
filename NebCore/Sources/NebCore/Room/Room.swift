import Foundation
import MatrixRustSDK
import os

private typealias SDKRoom = MatrixRustSDK.Room
private let logger = Logger(subsystem: "com.neb.app", category: "Room")

public final class Room: TimelineProtocol, MembersProtocol, RoomsProtocol, SearchProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private let roomListServiceProvider: () -> RoomListService?
    private let database: NebDatabase
    private let lock = NSLock()
    private var activeTimeline: (roomID: String, handle: TimelineHandle)?
    private var cachedTimelines: [String: TimelineHandle] = [:]
    private var cacheOrder: [String] = []
    private let maxCachedTimelines = 5
    private var setupGeneration: UInt64 = 0

    public init(
        clientProvider: @escaping () -> Client?,
        roomListServiceProvider: @escaping () -> RoomListService?,
        database: NebDatabase
    ) {
        self.clientProvider = clientProvider
        self.roomListServiceProvider = roomListServiceProvider
        self.database = database
    }

    // MARK: - TimelineProtocol

    public func startTimelineSync(roomID: String) async throws {
        // All mutation under NSLock must happen in a synchronous scope.
        // Returns nil on cache hit, or the generation number for a fresh setup.
        let myGeneration: UInt64? = lock.withLock {
            setupGeneration &+= 1
            let gen = setupGeneration

            if let active = activeTimeline, active.roomID != roomID {
                cachedTimelines[active.roomID] = active.handle
                cacheOrder.removeAll { $0 == active.roomID }
                cacheOrder.append(active.roomID)
                evictIfNeeded()
                activeTimeline = nil
            }

            if let cached = cachedTimelines.removeValue(forKey: roomID) {
                cacheOrder.removeAll { $0 == roomID }
                activeTimeline = (roomID: roomID, handle: cached)
                return nil  // cache hit
            }
            return gen
        }

        guard let myGeneration else {
            logger.info("Timeline cache hit for \(roomID)")
            return
        }

        guard let client = clientProvider() else {
            throw NebError.notLoggedIn
        }

        if let rls = roomListServiceProvider() {
            do {
                try await rls.subscribeToRooms(roomIds: [roomID])
                logger.info("Subscribed to room \(roomID)")
            } catch {
                logger.error("Failed to subscribe to room \(roomID): \(error)")
            }
        }

        guard isCurrentGeneration(myGeneration) else {
            logger.info("startTimelineSync: setup for \(roomID) cancelled by newer switch")
            return
        }

        guard let room = try? client.getRoom(roomId: roomID) else {
            throw NebError.roomNotFound(roomID)
        }

        let timeline: Timeline
        do {
            timeline = try await room.timeline()
        } catch {
            logger.error("startTimelineSync: failed to get timeline for \(roomID): \(error)")
            throw error
        }

        let myUserID = (try? client.userId()) ?? ""

        guard isCurrentGeneration(myGeneration) else {
            logger.info("startTimelineSync: setup for \(roomID) cancelled by newer switch")
            return
        }

        let listener = NebTimelineListener(
            roomID: roomID,
            myUserID: myUserID,
            database: database
        )

        let listenerHandle = await timeline.addListener(listener: listener)

        let handle = TimelineHandle(
            room: room,
            timeline: timeline,
            listener: listener,
            listenerHandle: listenerHandle
        )

        tryCommitActiveTimeline(roomID: roomID, handle: handle, generation: myGeneration)

        logger.info("Timeline listener active for \(roomID)")
        let _ = try? await timeline.paginateBackwards(numEvents: 50)

        Task {
            if let members = try? await room.membersNoSync() {
                while let chunk = members.nextChunk(chunkSize: 50) {
                    for member in chunk {
                        listener.cacheProfile(
                            userID: member.userId,
                            name: member.displayName ?? member.userId,
                            avatarURL: member.avatarUrl
                        )
                        try? database.upsertProfile(
                            userID: member.userId,
                            displayName: member.displayName ?? member.userId,
                            avatarURL: member.avatarUrl
                        )
                    }
                }
            }
        }
    }

    public func stopTimelineSync(roomID: String) async throws {
        let wasActive: Bool = lock.withLock {
            if let active = activeTimeline, active.roomID == roomID {
                cachedTimelines[active.roomID] = active.handle
                cacheOrder.removeAll { $0 == active.roomID }
                cacheOrder.append(active.roomID)
                evictIfNeeded()
                activeTimeline = nil
                return true
            }
            return false
        }
        if wasActive {
            logger.info("Timeline sync stopped for \(roomID), moved to cache")
        } else {
            logger.info("stopTimelineSync called for \(roomID) which is not active")
        }
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return setupGeneration == generation
    }

    private func tryCommitActiveTimeline(roomID: String, handle: TimelineHandle, generation: UInt64) {
        lock.lock()
        if setupGeneration == generation {
            activeTimeline = (roomID: roomID, handle: handle)
        } else {
            cachedTimelines[roomID] = handle
            cacheOrder.removeAll { $0 == roomID }
            cacheOrder.append(roomID)
            evictIfNeeded()
        }
        lock.unlock()
    }

    private func evictIfNeeded() {
        while cachedTimelines.count > maxCachedTimelines {
            if let oldest = cacheOrder.first {
                cacheOrder.removeFirst()
                cachedTimelines.removeValue(forKey: oldest)
            }
        }
    }

    public func send(roomID: String, body: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        let timeline = try await room.timeline()
        let content = messageEventContentFromMarkdown(md: body)
        // The SDK manages the full lifecycle: the NebTimelineListener will
        // receive .notSentYet → .sent (or .sendingFailed) and write to the DB.
        let _ = try await timeline.send(msg: content)
    }

    public func markAsRead(roomID: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        try await room.markAsRead(receiptType: .read)
    }

    public func createDM(userID: String) async throws -> String {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }

        if let existing = try client.getDmRoom(userId: userID) {
            return existing.id()
        }

        let params = CreateRoomParameters(
            name: nil,
            topic: nil,
            isEncrypted: true,
            isDirect: true,
            visibility: .private,
            preset: .trustedPrivateChat,
            invite: [userID],
            avatar: nil,
            powerLevelContentOverride: nil
        )
        return try await client.createRoom(request: params)
    }

    public func react(roomID: String, eventID: String, emoji: String) async throws {
        guard let handle = timelineHandle(for: roomID) else { throw NebError.roomNotFound(roomID) }
        let itemID: EventOrTransactionId = .eventId(eventId: eventID)
        let _ = try await handle.timeline.toggleReaction(itemId: itemID, key: emoji)
    }

    public func edit(roomID: String, eventID: String, newBody: String) async throws {
        guard let handle = timelineHandle(for: roomID) else { throw NebError.roomNotFound(roomID) }
        let itemID: EventOrTransactionId = .eventId(eventId: eventID)
        let content = messageEventContentFromMarkdown(md: newBody)
        try await handle.timeline.edit(eventOrTransactionId: itemID, newContent: .roomMessage(content: content))
    }

    public func sendReply(roomID: String, body: String, replyToEventID: String) async throws {
        guard let handle = timelineHandle(for: roomID) else { throw NebError.roomNotFound(roomID) }
        let content = messageEventContentFromMarkdown(md: body)
        try await handle.timeline.sendReply(msg: content, eventId: replyToEventID)
    }

    public func delete(roomID: String, eventID: String, reason: String?) async throws {
        guard let handle = timelineHandle(for: roomID) else { throw NebError.roomNotFound(roomID) }
        let itemID: EventOrTransactionId = .eventId(eventId: eventID)
        try await handle.timeline.redactEvent(eventOrTransactionId: itemID, reason: reason)
    }

    public func sendImage(roomID: String, url: URL, caption: String?) async throws {
        logger.warning("sendImage not yet implemented")
    }

    public func sendFile(roomID: String, url: URL, caption: String?) async throws {
        logger.warning("sendFile not yet implemented")
    }

    public func sendVideo(roomID: String, url: URL, thumbnailURL: URL, caption: String?) async throws {
        logger.warning("sendVideo not yet implemented")
    }

    // MARK: - MembersProtocol

    public func members(roomID: String) async throws -> [NebUser] {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        var users: [NebUser] = []
        let membersIterator = try await room.membersNoSync()
        while let chunk = membersIterator.nextChunk(chunkSize: 50) {
            for member in chunk {
                users.append(NebUser(
                    id: member.userId,
                    displayName: member.displayName,
                    avatarURL: member.avatarUrl
                ))
            }
        }
        return users
    }

    public func invite(roomID: String, userID: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        try await room.inviteUserById(userId: userID)
    }

    public func kick(roomID: String, userID: String, reason: String?) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        try await room.kickUser(userId: userID, reason: reason)
    }

    public func ban(roomID: String, userID: String, reason: String?) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        try await room.banUser(userId: userID, reason: reason)
    }

    public func unban(roomID: String, userID: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        try await room.unbanUser(userId: userID, reason: nil)
    }

    public func acceptInvite(roomID: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let _ = try await client.joinRoomById(roomId: roomID)
    }

    // MARK: - RoomsProtocol

    public func createRoom(name: String?, topic: String?, isEncrypted: Bool, isDirect: Bool, inviteUserIDs: [String]) async throws -> String {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let params = CreateRoomParameters(
            name: name,
            topic: topic,
            isEncrypted: isEncrypted,
            isDirect: isDirect,
            visibility: .private,
            preset: isDirect ? .trustedPrivateChat : .privateChat,
            invite: inviteUserIDs,
            avatar: nil,
            powerLevelContentOverride: nil
        )
        return try await client.createRoom(request: params)
    }

    public func joinRoom(roomIDOrAlias: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        let _ = try await client.joinRoomByIdOrAlias(roomIdOrAlias: roomIDOrAlias, serverNames: [])
    }

    public func leaveRoom(roomID: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        try await room.leave()
    }

    public func setRoomName(roomID: String, name: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        try await room.setName(name: name)
    }

    public func setRoomTopic(roomID: String, topic: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        try await room.setTopic(topic: topic)
    }

    public func setRoomAvatar(roomID: String, data: Data, mimeType: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        try await room.uploadAvatar(mimeType: mimeType, data: data, mediaInfo: nil)
    }

    public func roomInfo(roomID: String) async throws -> NebRoom {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        let info = try await room.roomInfo()
        return NebRoom(
            id: roomID,
            name: room.displayName() ?? roomID,
            avatarURL: info.avatarUrl,
            unreadCount: UInt(max(info.numUnreadMessages, info.numUnreadNotifications)),
            isDirect: info.isDirect,
            memberCount: UInt(info.activeMembersCount)
        )
    }

    @MainActor public func roomListStream() -> AsyncStream<[NebRoom]> {
        database.roomListObservation()
    }

    // MARK: - SearchProtocol

    public func search(query: String, roomID: String) async throws -> [SearchResult] {
        try database.search(query: query, roomID: roomID)
    }

    // MARK: - Typing

    public func sendTypingNotice(roomID: String, isTyping: Bool) async throws {
        guard let client = clientProvider() else { return }
        guard let room = try client.getRoom(roomId: roomID) else { return }
        try await room.typingNotice(isTyping: isTyping)
    }

    public func typingUsersStream(roomID: String) -> AsyncStream<[NebUser]> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            guard let client = self.clientProvider() else { return }
            guard let room = try? client.getRoom(roomId: roomID) else { return }

            let listener = NebTypingListener(roomID: roomID, room: room, continuation: continuation)
            let handle = room.subscribeToTypingNotifications(listener: listener)

            continuation.onTermination = { _ in
                _ = handle
            }
        }
    }

    // MARK: - Internal helpers

    private func timelineHandle(for roomID: String) -> TimelineHandle? {
        lock.lock()
        defer { lock.unlock() }
        if let active = activeTimeline, active.roomID == roomID {
            return active.handle
        }
        return cachedTimelines[roomID]
    }
}

private struct TimelineHandle {
    let room: SDKRoom
    let timeline: Timeline
    let listener: NebTimelineListener
    let listenerHandle: TaskHandle
}

private final class NebTimelineListener: TimelineListener, @unchecked Sendable {
    private let roomID: String
    private let myUserID: String
    private let database: NebDatabase
    private let lock = NSLock()
    nonisolated(unsafe) private var items: [TimelineItem] = []
    nonisolated(unsafe) private var profileCache: [String: (name: String, avatarURL: String?)] = [:]

    init(roomID: String, myUserID: String, database: NebDatabase) {
        self.roomID = roomID
        self.myUserID = myUserID
        self.database = database
    }

    func cacheProfile(userID: String, name: String, avatarURL: String?) {
        lock.lock()
        profileCache[userID] = (name: name, avatarURL: avatarURL)
        lock.unlock()
    }

    func onUpdate(diff: [TimelineDiff]) {
        lock.lock()
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

        // Process all current items and write to database
        for item in items {
            processItem(item)
        }
        lock.unlock()

        logger.info("Timeline \(self.roomID): processed \(self.items.count) items")
    }

    private func processItem(_ item: TimelineItem) {
        guard let event = item.asEvent() else { return }
        guard case .msgLike(let msgLike) = event.content else { return }

        // Extract sender profile
        var senderName = event.sender
        var senderAvatarURL: String? = nil
        switch event.senderProfile {
        case .ready(let displayName, _, let avatarUrl):
            if let name = displayName { senderName = name }
            senderAvatarURL = avatarUrl
        default:
            break
        }

        // Update profile cache and database
        profileCache[event.sender] = (name: senderName, avatarURL: senderAvatarURL)
        try? database.upsertProfile(
            userID: event.sender,
            displayName: senderName,
            avatarURL: senderAvatarURL
        )

        // Determine event/transaction ID
        let eventID: String
        var transactionID: String? = nil
        switch event.eventOrTransactionId {
        case .eventId(let id):
            eventID = id
        case .transactionId(let id):
            eventID = id
            transactionID = id
        }

        // Handle local send states. The SDK manages the send lifecycle:
        //   .notSentYet → insert with txn ID as PK, status "sending"
        //   .sent        → delete the txn row (real event arrives separately)
        //   .sendingFailed → insert/update with txn ID as PK, status "failed"
        if let localState = event.localSendState {
            switch localState {
            case .notSentYet(_):
                if case .message(let msgContent) = msgLike.kind {
                    let record = MessageRecord(
                        eventID: eventID,
                        roomID: roomID,
                        senderID: event.sender,
                        body: msgContent.body,
                        timestamp: TimeInterval(event.timestamp) / 1000,
                        sendStatus: "sending",
                        transactionID: transactionID
                    )
                    try? database.insertMessage(record)
                }
                return

            case .sent(_):
                // The local echo is confirmed. Delete the txn row — the real
                // event will arrive as a regular timeline item and be inserted
                // with its permanent event ID.
                try? database.deleteMessage(eventID: eventID)
                return

            case .sendingFailed(_, _):
                if case .message(let msgContent) = msgLike.kind {
                    let record = MessageRecord(
                        eventID: eventID,
                        roomID: roomID,
                        senderID: event.sender,
                        body: msgContent.body,
                        timestamp: TimeInterval(event.timestamp) / 1000,
                        sendStatus: "failed",
                        transactionID: transactionID
                    )
                    try? database.insertMessage(record)
                }
                try? database.updateSendStatus(eventID: eventID, status: "failed")
                return
            }
        }

        // Process confirmed message content
        switch msgLike.kind {
        case .message(let msgContent):
            let body = msgContent.body
            let isEdited = msgContent.isEdited
            var formattedBody: String? = nil
            if case .text(let textContent) = msgContent.msgType,
               let formatted = textContent.formatted,
               case .html = formatted.format {
                formattedBody = formatted.body
            }

            let timestamp = TimeInterval(event.timestamp) / 1000

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

            if isEdited {
                try? database.updateMessageBody(
                    eventID: eventID,
                    body: body,
                    formattedBody: formattedBody,
                    isEdited: true
                )
            }
            try? database.insertMessage(record)

        case .unableToDecrypt:
            let record = MessageRecord(
                eventID: eventID,
                roomID: roomID,
                senderID: event.sender,
                body: "\u{1F512} Encrypted message (verify this device to decrypt)",
                timestamp: TimeInterval(event.timestamp) / 1000,
                sendStatus: "sent"
            )
            try? database.insertMessage(record)

        default:
            return
        }

        // Write reactions
        let reactionRecords = msgLike.reactions.flatMap { reaction in
            reaction.senders.map { sender in
                ReactionRecord(eventID: eventID, emoji: reaction.key, senderID: sender.senderId)
            }
        }
        try? database.replaceReactions(eventID: eventID, reactions: reactionRecords)

        // Write read receipts
        for (userID, _) in event.readReceipts {
            try? database.upsertReadReceipt(roomID: roomID, userID: userID, eventID: eventID)
        }
    }
}

private final class NebTypingListener: TypingNotificationsListener, @unchecked Sendable {
    private let roomID: String
    private let room: SDKRoom
    private let continuation: AsyncStream<[NebUser]>.Continuation

    init(roomID: String, room: SDKRoom, continuation: AsyncStream<[NebUser]>.Continuation) {
        self.roomID = roomID
        self.room = room
        self.continuation = continuation
    }

    func call(typingUserIds: [String]) {
        Task {
            var users: [NebUser] = []
            for userID in typingUserIds {
                var displayName: String? = nil
                var avatarURL: String? = nil

                if let members = try? await room.membersNoSync() {
                    while let chunk = members.nextChunk(chunkSize: 50) {
                        for member in chunk {
                            if member.userId == userID {
                                displayName = member.displayName
                                avatarURL = member.avatarUrl
                                break
                            }
                        }
                        if displayName != nil { break }
                    }
                }

                users.append(NebUser(
                    id: userID,
                    displayName: displayName,
                    avatarURL: avatarURL
                ))
            }
            continuation.yield(users)
        }
    }
}
