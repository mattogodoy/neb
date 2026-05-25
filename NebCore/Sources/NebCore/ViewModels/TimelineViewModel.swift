import Foundation

@MainActor
@Observable
public final class TimelineViewModel {
    public private(set) var messages: [NebMessage] = []
    public private(set) var typingUsers: [NebUser] = []
    public private(set) var isLoadingMore = false
    public var composerText: String = ""
    public private(set) var editingMessage: NebMessage?

    private let roomID: String
    private let roomService: any RoomServiceProtocol
    private let typingService: (any TypingServiceProtocol)?
    private let currentUserID: String?
    @ObservationIgnored nonisolated(unsafe) private var timelineTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var typingTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var typingDebounceTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var isCurrentlyTyping = false

    public init(
        roomID: String,
        roomService: any RoomServiceProtocol,
        typingService: (any TypingServiceProtocol)? = nil,
        currentUserID: String? = nil
    ) {
        self.roomID = roomID
        self.roomService = roomService
        self.typingService = typingService
        self.currentUserID = currentUserID
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
        } catch {}
    }

    public func markAsRead() async {
        guard let lastMessage = messages.last else { return }
        do {
            try await roomService.sendReadReceipt(roomID: roomID, eventID: lastMessage.id)
        } catch {}
    }

    public func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        do {
            try await roomService.paginateBackwards(roomID: roomID, count: 50)
        } catch {}
        isLoadingMore = false
    }

    public func toggleReaction(eventID: String, emoji: String) async {
        do {
            try await roomService.toggleReaction(roomID: roomID, eventID: eventID, emoji: emoji)
        } catch {}
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
        } catch {}
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
                await self.markAsRead()
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
