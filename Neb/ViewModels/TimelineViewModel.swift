import NebCore
import Foundation
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Timeline")

@MainActor
@Observable
public final class TimelineViewModel {
    public private(set) var messages: [NebMessage] = []
    public private(set) var typingUsers: [NebUser] = []
    public private(set) var isLoadingMore = false
    public private(set) var hasLoadedInitialTimeline = false
    public var composerText: String = ""
    public var editingMessage: NebMessage?
    public let initialUnreadCount: UInt

    private let roomID: String
    private let roomService: any RoomProtocol
    private let typingService: (any TypingProtocol)?
    private let currentUserID: String?
    @ObservationIgnored nonisolated(unsafe) private var timelineTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var typingTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var typingDebounceTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var isCurrentlyTyping = false

    public init(
        roomID: String,
        roomService: any RoomProtocol,
        typingService: (any TypingProtocol)? = nil,
        currentUserID: String? = nil,
        initialUnreadCount: UInt = 0
    ) {
        self.roomID = roomID
        self.roomService = roomService
        self.typingService = typingService
        self.currentUserID = currentUserID
        self.initialUnreadCount = initialUnreadCount
        startObserving()
        startTypingObserving()
    }

    deinit {
        timelineTask?.cancel()
        typingTask?.cancel()
        typingDebounceTask?.cancel()
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
            try await roomService.sendMessage(roomID: roomID, body: trimmed)
        } catch { logger.error("Failed to send message in \(self.roomID): \(error)") }
    }

    public func markAsRead() async {
        guard let lastMessage = messages.last else { return }
        do {
            try await roomService.sendReadReceipt(roomID: roomID, eventID: lastMessage.id)
        } catch { logger.error("Failed to send read receipt in \(self.roomID): \(error)") }
    }

    public func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        do {
            try await roomService.paginateBackwards(roomID: roomID, count: 50)
            try? await Task.sleep(for: .milliseconds(500))
        } catch { logger.error("Failed to paginate backwards in \(self.roomID): \(error)") }
        isLoadingMore = false
    }

    public func toggleReaction(eventID: String, emoji: String) async {
        do {
            try await roomService.toggleReaction(roomID: roomID, eventID: eventID, emoji: emoji)
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
            try await roomService.editMessage(roomID: roomID, eventID: editing.id, newBody: newBody)
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
        timelineTask = Task { [weak self] in
            guard let self else { return }
            for await messages in self.roomService.timelineStream(roomID: self.roomID) {
                guard !Task.isCancelled else { break }
                self.messages = messages
                self.hasLoadedInitialTimeline = true
            }
        }
    }

    private func startTypingObserving() {
        guard let typingService else { return }
        typingTask = Task { [weak self] in
            guard let self else { return }
            for await users in typingService.typingUsersStream(roomID: self.roomID) {
                guard !Task.isCancelled else { break }
                if let myID = self.currentUserID {
                    self.typingUsers = users.filter { $0.id != myID }
                } else {
                    self.typingUsers = users
                }
            }
        }
    }
}
