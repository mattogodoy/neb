import NebCore
import Foundation
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Timeline")

@MainActor
@Observable
public final class TimelineViewModel {
    public private(set) var messages: [NebMessage] = []
    public private(set) var messageLayouts: [String: MessageLayout] = [:]
    public private(set) var typingUsers: [NebUser] = []
    public private(set) var isLoadingMore = false
    public private(set) var hasLoadedInitialTimeline = false
    public var composerText: String = ""
    public var editingMessage: NebMessage?
    public let initialUnreadCount: UInt

    private let roomID: String
    private let roomService: any TimelineProtocol
    private let database: NebDatabase
    private let currentUserID: String
    private let typingService: (any TypingProtocol)?
    private var messageLimit = 50
    @ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var syncTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var typingTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var typingDebounceTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var isCurrentlyTyping = false

    public init(
        roomID: String,
        roomService: any TimelineProtocol,
        database: NebDatabase,
        currentUserID: String,
        typingService: (any TypingProtocol)? = nil,
        initialUnreadCount: UInt = 0
    ) {
        self.roomID = roomID
        self.roomService = roomService
        self.database = database
        self.currentUserID = currentUserID
        self.typingService = typingService
        self.initialUnreadCount = initialUnreadCount
        startObserving()
        startTypingObserving()
        syncTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.roomService.startTimelineSync(roomID: self.roomID)
            } catch {
                logger.error("Failed to start timeline sync for \(self.roomID): \(error)")
            }
        }
    }

    deinit {
        observationTask?.cancel()
        typingTask?.cancel()
        typingDebounceTask?.cancel()
        syncTask?.cancel()
        let roomService = self.roomService
        let roomID = self.roomID
        Task { try? await roomService.stopTimelineSync(roomID: roomID) }
    }

    public func onComposerChanged(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            stopTyping()
            return
        }

        if !isCurrentlyTyping {
            isCurrentlyTyping = true
            Task { try? await typingService?.sendTypingNotice(roomID: roomID, isTyping: true) }
        }

        typingDebounceTask?.cancel()
        typingDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.stopTyping()
        }
    }

    public func sendMessage(_ body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stopTyping()
        do {
            try await roomService.send(roomID: roomID, body: trimmed)
        } catch { logger.error("Failed to send message in \(self.roomID): \(error)") }
    }

    public func markAsRead() async {
        guard !messages.isEmpty else { return }
        do {
            try await roomService.markAsRead(roomID: roomID)
        } catch { logger.error("Failed to send read receipt in \(self.roomID): \(error)") }
    }

    public func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        messageLimit += 50
        restartObservation()
        try? await Task.sleep(for: .milliseconds(200))
        isLoadingMore = false
    }

    public func toggleReaction(eventID: String, emoji: String) async {
        do {
            try await roomService.react(roomID: roomID, eventID: eventID, emoji: emoji)
        } catch { logger.error("Failed to toggle reaction in \(self.roomID): \(error)") }
    }

    public func startEditingLastMessage() {
        guard let last = messages.last(where: { $0.isOutgoing && $0.isEditable }) else { return }
        editingMessage = last
        composerText = last.body
    }

    public func cancelEditing() {
        editingMessage = nil
        composerText = ""
    }

    public func submitEdit() async {
        guard let editing = editingMessage else { return }
        let newBody = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newBody.isEmpty, newBody != editing.body else {
            cancelEditing()
            return
        }
        do {
            try await roomService.edit(roomID: roomID, eventID: editing.id, newBody: newBody)
        } catch { logger.error("Failed to edit message \(editing.id) in \(self.roomID): \(error)") }
        editingMessage = nil
        composerText = ""
    }

    private func stopTyping() {
        guard isCurrentlyTyping else { return }
        isCurrentlyTyping = false
        typingDebounceTask?.cancel()
        typingDebounceTask = nil
        Task { try? await typingService?.sendTypingNotice(roomID: roomID, isTyping: false) }
    }

    private func startObserving() {
        let stream = database.observeMessages(roomID: roomID, limit: messageLimit)
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await rows in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.messages = rows.map { self.toNebMessage($0) }
                    self.messageLayouts = Self.computeLayouts(for: self.messages)
                    self.hasLoadedInitialTimeline = true
                }
            }
        }
    }

    private func restartObservation() {
        observationTask?.cancel()
        startObserving()
    }

    private func toNebMessage(_ row: MessageWithProfile) -> NebMessage {
        let m = row.message
        let isOutgoing = m.senderID == currentUserID
        let sendStatus: SendStatus = switch m.sendStatus {
        case "pending", "sending": .sending
        case "failed": .failed
        default: .sent
        }
        return NebMessage(
            id: m.eventID,
            roomID: m.roomID,
            senderID: m.senderID,
            senderDisplayName: row.displayName ?? m.senderID,
            senderAvatarURL: row.avatarURL,
            body: m.body,
            formattedBody: m.formattedBody,
            timestamp: Date(timeIntervalSince1970: m.timestamp),
            isOutgoing: isOutgoing,
            sendStatus: sendStatus,
            readReceipts: [],
            reactions: [],
            isEdited: m.isEdited,
            isEditable: isOutgoing && m.sendStatus == "sent",
            isEmojiOnly: m.body.isEmojiOnly
        )
    }

    private static func computeLayouts(for messages: [NebMessage]) -> [String: MessageLayout] {
        var layouts: [String: MessageLayout] = [:]
        layouts.reserveCapacity(messages.count)
        for i in messages.indices {
            let msg = messages[i]
            let prev: NebMessage? = i > 0 ? messages[i - 1] : nil
            let next: NebMessage? = i < messages.count - 1 ? messages[i + 1] : nil

            let isFirst = isFirstInGroup(current: msg, previous: prev)
            let isLast = isLastInGroup(current: msg, next: next)

            let position: MessageGroupPosition
            switch (isFirst, isLast) {
            case (true, true): position = .alone
            case (true, false): position = .first
            case (false, true): position = .last
            case (false, false): position = .middle
            }

            let showDay: Bool
            if let prev {
                showDay = !Calendar.current.isDate(prev.timestamp, inSameDayAs: msg.timestamp)
            } else {
                showDay = true
            }

            layouts[msg.id] = MessageLayout(groupPosition: position, showDaySeparator: showDay)
        }
        return layouts
    }

    private static func isFirstInGroup(current: NebMessage, previous: NebMessage?) -> Bool {
        guard let prev = previous else { return true }
        if prev.senderID != current.senderID { return true }
        if current.timestamp.timeIntervalSince(prev.timestamp) > 300 { return true }
        if !Calendar.current.isDate(prev.timestamp, inSameDayAs: current.timestamp) { return true }
        return false
    }

    private static func isLastInGroup(current: NebMessage, next: NebMessage?) -> Bool {
        guard let next = next else { return true }
        if next.senderID != current.senderID { return true }
        if next.timestamp.timeIntervalSince(current.timestamp) > 300 { return true }
        if !Calendar.current.isDate(next.timestamp, inSameDayAs: current.timestamp) { return true }
        return false
    }

    private func startTypingObserving() {
        guard let typingService else { return }
        typingTask = Task { [weak self] in
            guard let self else { return }
            for await users in typingService.typingUsersStream(roomID: self.roomID) {
                guard !Task.isCancelled else { break }
                let myID = self.currentUserID
                self.typingUsers = users.filter { $0.id != myID }
            }
        }
    }
}
