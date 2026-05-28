import Foundation
import MatrixRustSDK
import os

private typealias SDKRoom = MatrixRustSDK.Room
private let logger = Logger(subsystem: "com.neb.app", category: "Room")

public final class Room: TimelineProtocol, MembersProtocol, RoomsProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private let roomListServiceProvider: () -> RoomListService?
    private let lock = NSLock()
    private var activeTimeline: (roomID: String, handle: TimelineHandle)?
    private var cachedTimelines: [String: TimelineHandle] = [:]
    private var cacheOrder: [String] = []
    private let maxCachedTimelines = 5
    private var setupGeneration: UInt64 = 0

    public init(clientProvider: @escaping () -> Client?, roomListServiceProvider: @escaping () -> RoomListService?) {
        self.clientProvider = clientProvider
        self.roomListServiceProvider = roomListServiceProvider
    }

    public func messageStream(roomID: String) -> AsyncStream<[NebMessage]> {
        lock.lock()
        setupGeneration &+= 1
        let myGeneration = setupGeneration

        if let active = activeTimeline, active.roomID != roomID {
            active.handle.listener.detachContinuation()
            cachedTimelines[active.roomID] = active.handle
            cacheOrder.removeAll { $0 == active.roomID }
            cacheOrder.append(active.roomID)
            evictIfNeeded()
            activeTimeline = nil
        }

        if let cached = cachedTimelines.removeValue(forKey: roomID) {
            cacheOrder.removeAll { $0 == roomID }
            activeTimeline = (roomID: roomID, handle: cached)
            lock.unlock()
            logger.info("Timeline cache hit for \(roomID)")

            return AsyncStream { continuation in
                cached.listener.attachContinuation(continuation)
            }
        }
        lock.unlock()

        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            Task {
                guard let client = self.clientProvider() else {
                    logger.error("timelineStream: not logged in")
                    continuation.finish()
                    return
                }
                if let rls = self.roomListServiceProvider() {
                    do {
                        try await rls.subscribeToRooms(roomIds: [roomID])
                        logger.info("Subscribed to room \(roomID)")
                    } catch {
                        logger.error("Failed to subscribe to room \(roomID): \(error)")
                    }
                }

                guard self.isCurrentGeneration(myGeneration) else {
                    logger.info("timelineStream: setup for \(roomID) cancelled by newer switch")
                    continuation.finish()
                    return
                }

                guard let room = try? client.getRoom(roomId: roomID) else {
                    logger.error("timelineStream: room \(roomID) not found")
                    continuation.finish()
                    return
                }

                let timeline: Timeline
                do {
                    timeline = try await room.timeline()
                } catch {
                    logger.error("timelineStream: failed to get timeline for \(roomID): \(error)")
                    continuation.finish()
                    return
                }
                let myUserID = (try? client.userId()) ?? ""

                guard self.isCurrentGeneration(myGeneration) else {
                    logger.info("timelineStream: setup for \(roomID) cancelled by newer switch")
                    continuation.finish()
                    return
                }

                let listener = NebTimelineListener(
                    roomID: roomID,
                    myUserID: myUserID,
                    continuation: continuation
                )

                let listenerHandle = await timeline.addListener(listener: listener)

                let handle = TimelineHandle(
                    room: room,
                    timeline: timeline,
                    listener: listener,
                    listenerHandle: listenerHandle
                )

                self.tryCommitActiveTimeline(roomID: roomID, handle: handle, generation: myGeneration)

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
                            }
                        }
                        listener.refreshMessages()
                    }
                }
            }
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
            handle.listener.detachContinuation()
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

    public func paginateBackwards(roomID: String, count: UInt) async throws {
        guard let handle = timelineHandle(for: roomID) else { throw NebError.roomNotFound(roomID) }
        let _ = try await handle.timeline.paginateBackwards(numEvents: UInt16(min(count, UInt(UInt16.max))))
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
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: AsyncStream<[NebMessage]>.Continuation?
    nonisolated(unsafe) private var items: [TimelineItem] = []
    nonisolated(unsafe) private var profileCache: [String: (name: String, avatarURL: String?)] = [:]

    init(roomID: String, myUserID: String, continuation: AsyncStream<[NebMessage]>.Continuation) {
        self.roomID = roomID
        self.myUserID = myUserID
        self.continuation = continuation
    }

    func attachContinuation(_ newContinuation: AsyncStream<[NebMessage]>.Continuation) {
        lock.lock()
        continuation = newContinuation
        let messages = items.compactMap { convertItem($0) }
        lock.unlock()
        newContinuation.yield(messages)
    }

    func detachContinuation() {
        lock.lock()
        let old = continuation
        continuation = nil
        lock.unlock()
        old?.finish()
    }

    func refreshMessages() {
        lock.lock()
        let cont = continuation
        let messages = items.compactMap { convertItem($0) }
        lock.unlock()
        cont?.yield(messages)
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

        let cont = continuation
        let messages = items.compactMap { convertItem($0) }
        lock.unlock()

        if let cont {
            logger.info("Timeline \(self.roomID): \(messages.count) messages")
            cont.yield(messages)
        }
    }

    private func convertItem(_ item: TimelineItem) -> NebMessage? {
        guard let event = item.asEvent() else { return nil }
        guard case .msgLike(let msgLike) = event.content else { return nil }

        let body: String
        var isEdited = false
        var formattedBody: String? = nil
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
            return nil
        }

        let eventID: String
        switch event.eventOrTransactionId {
        case .eventId(let id):
            eventID = id
        case .transactionId(let id):
            eventID = id
        }

        var senderName = event.sender
        var senderAvatarURL: String? = nil
        switch event.senderProfile {
        case .ready(let displayName, _, let avatarUrl):
            if let name = displayName { senderName = name }
            senderAvatarURL = avatarUrl
        default:
            break
        }

        profileCache[event.sender] = (name: senderName, avatarURL: senderAvatarURL)

        let sendStatus: SendStatus
        if let localState = event.localSendState {
            switch localState {
            case .notSentYet(_):
                sendStatus = .sending
            case .sendingFailed(_, _):
                sendStatus = .failed
            case .sent(_):
                sendStatus = .sent
            }
        } else {
            sendStatus = .sent
        }

        let readReceipts: [ReadReceipt] = event.readReceipts
            .filter { $0.key != myUserID }
            .map { (userID, _) in
                let cached = profileCache[userID]
                return ReadReceipt(
                    userID: userID,
                    displayName: cached?.name ?? userID,
                    avatarURL: cached?.avatarURL
                )
            }

        let reactions: [NebReaction] = msgLike.reactions.map { reaction in
            NebReaction(
                emoji: reaction.key,
                count: reaction.senders.count,
                senderIDs: reaction.senders.map(\.senderId),
                includesMe: reaction.senders.contains { $0.senderId == myUserID }
            )
        }

        return NebMessage(
            id: eventID,
            roomID: roomID,
            senderID: event.sender,
            senderDisplayName: senderName,
            senderAvatarURL: senderAvatarURL,
            body: body,
            formattedBody: formattedBody,
            timestamp: Date(timeIntervalSince1970: TimeInterval(event.timestamp) / 1000),
            isOutgoing: event.isOwn,
            sendStatus: sendStatus,
            readReceipts: readReceipts,
            reactions: reactions,
            isEdited: isEdited,
            isEditable: event.isEditable && event.isOwn,
            isEmojiOnly: body.isEmojiOnly
        )
    }
}
