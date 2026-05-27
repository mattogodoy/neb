import Foundation
import MatrixRustSDK
import os

private typealias SDKRoom = MatrixRustSDK.Room
private let logger = Logger(subsystem: "com.neb.app", category: "Room")

public final class Room: RoomServiceProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private let roomListServiceProvider: () -> RoomListService?
    private var activeTimelines: [String: TimelineHandle] = [:]

    public init(clientProvider: @escaping () -> Client?, roomListServiceProvider: @escaping () -> RoomListService?) {
        self.clientProvider = clientProvider
        self.roomListServiceProvider = roomListServiceProvider
    }

    public func timelineStream(roomID: String) -> AsyncStream<[NebMessage]> {
        activeTimelines.removeValue(forKey: roomID)

        return AsyncStream { [weak self] continuation in
            guard let self else { return }

            Task {
                guard let client = self.clientProvider() else {
                    logger.error("timelineStream: not logged in")
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

                guard let room = try? client.getRoom(roomId: roomID) else {
                    logger.error("timelineStream: room \(roomID) not found")
                    return
                }

                let timeline = try await room.timeline()
                let myUserID = (try? client.userId()) ?? ""

                let listener = NebTimelineListener(
                    roomID: roomID,
                    myUserID: myUserID,
                    continuation: continuation
                )

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
                }

                let listenerHandle = await timeline.addListener(listener: listener)

                self.activeTimelines[roomID] = TimelineHandle(
                    room: room,
                    timeline: timeline,
                    listener: listener,
                    listenerHandle: listenerHandle
                )

                logger.info("Timeline listener active for \(roomID)")
                let _ = try? await timeline.paginateBackwards(numEvents: 50)
            }
        }
    }

    public func sendMessage(roomID: String, body: String) async throws {
        guard let client = clientProvider() else { throw NebError.notLoggedIn }
        guard let room = try client.getRoom(roomId: roomID) else { throw NebError.roomNotFound(roomID) }
        let timeline = try await room.timeline()
        let content = messageEventContentFromMarkdown(md: body)
        let _ = try await timeline.send(msg: content)
    }

    public func sendReadReceipt(roomID: String, eventID: String) async throws {
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
        guard let handle = activeTimelines[roomID] else { throw NebError.roomNotFound(roomID) }
        let _ = try await handle.timeline.paginateBackwards(numEvents: UInt16(min(count, UInt(UInt16.max))))
    }

    public func toggleReaction(roomID: String, eventID: String, emoji: String) async throws {
        guard let handle = activeTimelines[roomID] else { throw NebError.roomNotFound(roomID) }
        let itemID: EventOrTransactionId = .eventId(eventId: eventID)
        let _ = try await handle.timeline.toggleReaction(itemId: itemID, key: emoji)
    }

    public func editMessage(roomID: String, eventID: String, newBody: String) async throws {
        guard let handle = activeTimelines[roomID] else { throw NebError.roomNotFound(roomID) }
        let itemID: EventOrTransactionId = .eventId(eventId: eventID)
        let content = messageEventContentFromMarkdown(md: newBody)
        try await handle.timeline.edit(eventOrTransactionId: itemID, newContent: .roomMessage(content: content))
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
    private let continuation: AsyncStream<[NebMessage]>.Continuation
    nonisolated(unsafe) private var items: [TimelineItem] = []
    nonisolated(unsafe) private var profileCache: [String: (name: String, avatarURL: String?)] = [:]

    init(roomID: String, myUserID: String, continuation: AsyncStream<[NebMessage]>.Continuation) {
        self.roomID = roomID
        self.myUserID = myUserID
        self.continuation = continuation
    }

    func cacheProfile(userID: String, name: String, avatarURL: String?) {
        profileCache[userID] = (name: name, avatarURL: avatarURL)
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

        if !items.isEmpty {
            var eventCount = 0
            var virtualCount = 0
            var msgCount = 0
            var encryptedCount = 0
            var otherContentTypes: [String] = []
            for item in items {
                if let event = item.asEvent() {
                    eventCount += 1
                    switch event.content {
                    case .msgLike(let ml):
                        switch ml.kind {
                        case .message: msgCount += 1
                        case .unableToDecrypt: encryptedCount += 1
                        default: otherContentTypes.append("msgLike-other")
                        }
                    default:
                        otherContentTypes.append(String(describing: event.content).prefix(40).description)
                    }
                } else {
                    virtualCount += 1
                }
            }
            logger.info("Timeline \(self.roomID) raw: \(self.items.count) items, \(eventCount) events, \(msgCount) msg, \(encryptedCount) encrypted, \(virtualCount) virtual, other: \(otherContentTypes.joined(separator: ","))")
        }

        let messages = items.compactMap { convertItem($0) }
        logger.info("Timeline \(self.roomID): \(messages.count) messages")
        continuation.yield(messages)
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
            isEditable: event.isEditable && event.isOwn
        )
    }
}
