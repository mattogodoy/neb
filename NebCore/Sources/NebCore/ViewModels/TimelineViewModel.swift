import Foundation

@MainActor
@Observable
public final class TimelineViewModel {
    public private(set) var messages: [NebMessage] = []
    public private(set) var isLoadingMore = false
    public var composerText: String = ""

    private let roomID: String
    private let roomService: any RoomServiceProtocol
    @ObservationIgnored nonisolated(unsafe) private var timelineTask: Task<Void, Never>?

    public init(roomID: String, roomService: any RoomServiceProtocol) {
        self.roomID = roomID
        self.roomService = roomService
        startObserving()
    }

    deinit {
        timelineTask?.cancel()
    }

    public func sendMessage(_ body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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
}
