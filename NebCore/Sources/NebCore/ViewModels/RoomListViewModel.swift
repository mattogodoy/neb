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

    public init(syncService: any SyncServiceProtocol, notificationService: (any NotificationServiceProtocol)? = nil) {
        self.syncService = syncService
        self.notificationService = notificationService
        startObserving()
    }

    deinit {
        syncTask?.cancel()
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
                await self.notificationService?.updateBadgeCount(self.totalUnreadCount)
                await self.postNotificationsForNewMessages(oldRooms: oldRooms, newRooms: rooms)
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
