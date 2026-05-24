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
    @ObservationIgnored nonisolated(unsafe) private var syncTask: Task<Void, Never>?

    public init(syncService: any SyncServiceProtocol) {
        self.syncService = syncService
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
                self.allRooms = rooms
            }
        }
    }
}
