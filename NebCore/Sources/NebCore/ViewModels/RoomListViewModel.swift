import Foundation

@MainActor
@Observable
public final class RoomListViewModel {
    public private(set) var allRooms: [NebRoom] = []
    public var selectedRoom: NebRoom?
    public var searchQuery: String = ""

    public var directMessages: [NebRoom] {
        filteredRooms.filter(\.isDirect)
    }

    public var groups: [NebRoom] {
        filteredRooms.filter { !$0.isDirect }
    }

    public var totalUnreadCount: UInt {
        allRooms.reduce(0) { $0 + $1.unreadCount }
    }

    private var filteredRooms: [NebRoom] {
        if searchQuery.isEmpty { return allRooms }
        let query = searchQuery.lowercased()
        return allRooms.filter { $0.name.lowercased().contains(query) }
    }

    private let syncService: any SyncServiceProtocol
    private let notificationService: (any NotificationServiceProtocol)?
    private var previousUnreadCounts: [String: UInt] = [:]
    @ObservationIgnored nonisolated(unsafe) private var syncTask: Task<Void, Never>?
    private let typingService: (any TypingServiceProtocol)?
    private var roomTypingUsers: [String: [NebUser]] = [:]
    @ObservationIgnored nonisolated(unsafe) private var typingTasks: [String: Task<Void, Never>] = [:]

    public init(
        syncService: any SyncServiceProtocol,
        notificationService: (any NotificationServiceProtocol)? = nil,
        typingService: (any TypingServiceProtocol)? = nil
    ) {
        self.syncService = syncService
        self.notificationService = notificationService
        self.typingService = typingService
        startObserving()
    }

    deinit {
        syncTask?.cancel()
        for task in typingTasks.values { task.cancel() }
    }

    public func typingUsers(for roomID: String) -> [NebUser] {
        roomTypingUsers[roomID] ?? []
    }

    public func selectRoom(_ room: NebRoom?) {
        selectedRoom = room
    }

    public func setSearchQuery(_ query: String) {
        searchQuery = query
    }

    private func startObserving() {
        syncTask = Task { [weak self] in
            guard let self else { return }
            for await rooms in self.syncService.roomListStream() {
                guard !Task.isCancelled else { break }

                let oldRooms = self.allRooms
                self.allRooms = rooms
                self.updateTypingSubscriptions(for: rooms)
                await self.notificationService?.updateBadgeCount(self.totalUnreadCount)
                await self.postNotificationsForNewMessages(oldRooms: oldRooms, newRooms: rooms)
            }
        }
    }

    private func updateTypingSubscriptions(for rooms: [NebRoom]) {
        guard let typingService else { return }

        let currentRoomIDs = Set(rooms.map(\.id))
        let subscribedRoomIDs = Set(typingTasks.keys)

        // Cancel subscriptions for rooms no longer in the list
        for roomID in subscribedRoomIDs.subtracting(currentRoomIDs) {
            typingTasks[roomID]?.cancel()
            typingTasks.removeValue(forKey: roomID)
            roomTypingUsers.removeValue(forKey: roomID)
        }

        // Subscribe to new rooms
        for roomID in currentRoomIDs.subtracting(subscribedRoomIDs) {
            typingTasks[roomID] = Task { [weak self] in
                for await users in typingService.typingUsersStream(roomID: roomID) {
                    guard !Task.isCancelled else { break }
                    self?.roomTypingUsers[roomID] = users
                }
            }
        }
    }

    private func postNotificationsForNewMessages(oldRooms: [NebRoom], newRooms: [NebRoom]) async {
        guard let notificationService else { return }

        for room in newRooms {
            let oldCount = previousUnreadCounts[room.id] ?? 0
            let isSelected = selectedRoom?.id == room.id

            if room.unreadCount > oldCount && !isSelected {
                let body = room.lastMessage ?? "New message"
                await notificationService.postNotification(
                    title: room.name,
                    body: body,
                    roomID: room.id
                )
            }
            previousUnreadCounts[room.id] = room.unreadCount
        }
    }
}
