# Sync Refactor -- Database-Backed Room List and Clean Domain Boundaries

## Problem

`MatrixSyncAdapter` does two unrelated things: manages the SDK sync connection and produces the room list. The room list is a room concern, not a sync concern. The room list is also built from live SDK objects on every update -- it should come from the database like messages do.

## Goal

- Sync manages the connection. Writes room metadata and events to the database.
- Room reads from the database. Room list, timeline, search -- all database-backed.
- `SyncProtocol` exposes only connection lifecycle and status.
- `RoomsProtocol` gains `roomListStream()`.
- New `rooms` table in the database.
- `MatrixSyncAdapter` renamed to `Sync`.

## SyncProtocol

```swift
public protocol SyncProtocol: Sendable {
    func start() async throws
    func stop() async throws
    var isOnline: Bool { get }
    func statusStream() -> AsyncStream<Bool>
}
```

The app calls `start()` on login and `stop()` on logout. View models can observe `statusStream()` to show a connection indicator. `roomListStream()` is removed from `SyncProtocol`.

## Sync (renamed from MatrixSyncAdapter)

Conforms to `SyncProtocol`. Manages the SDK's `SyncService` and `RoomListService`.

### What Sync writes to the database

On every room list update from the SDK (via `RoomListEntriesListener`):

1. Apply diffs to the internal `[SDKRoom]` array (same as current code).
2. For each room, fetch `roomInfo()` and write/update the `rooms` table: name, avatarURL, unreadCount, isDirect, directUserID, memberCount.
3. Use `INSERT OR REPLACE` (upsert) on the rooms table -- the room's metadata is fully replaced on each update.

The current `convertAndEmit` method (which builds `[NebRoom]` and yields to continuations) is replaced by database writes. No more continuations or `latestNebRooms` cache -- the database is the cache.

### Connection status

The SDK's `SyncService` has a state that indicates whether sync is running. `Sync` tracks this and exposes it via `isOnline` and `statusStream()`.

### roomListService

Still exposed internally (not via protocol) for Room and BackfillWorker to subscribe to rooms before timeline operations. Accessed via a closure in Room's init, same as today.

## Database Changes

### New `rooms` table

| Column | Type | Notes |
|--------|------|-------|
| `roomID` | TEXT | Primary key. |
| `name` | TEXT | NOT NULL. Display name. |
| `avatarURL` | TEXT | Nullable. MXC URI. |
| `unreadCount` | INTEGER | NOT NULL, default 0. From SDK's numUnreadMessages/numUnreadNotifications. |
| `isDirect` | INTEGER | NOT NULL, default 0. Boolean. |
| `directUserID` | TEXT | Nullable. The other user in a DM. |
| `memberCount` | INTEGER | NOT NULL, default 0. Active members count. |

### New `RoomRecord`

```swift
public struct RoomRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "rooms"

    public var roomID: String
    public var name: String
    public var avatarURL: String?
    public var unreadCount: Int
    public var isDirect: Bool
    public var directUserID: String?
    public var memberCount: Int
}
```

### NebDatabase methods

Write (used by Sync):

```swift
func upsertRoom(_ room: RoomRecord) throws
func deleteRoom(roomID: String) throws
```

Observation (used by Room):

```swift
func roomListObservation() -> AsyncStream<[NebRoom]>
```

The room list query joins rooms with the latest message from the messages table:

```sql
SELECT r.*,
       m.body AS lastMessage,
       m.timestamp AS lastMessageTimestamp
FROM rooms r
LEFT JOIN (
    SELECT roomID, body, timestamp,
           ROW_NUMBER() OVER (PARTITION BY roomID ORDER BY timestamp DESC) AS rn
    FROM messages
) m ON r.roomID = m.roomID AND m.rn = 1
ORDER BY COALESCE(m.timestamp, 0) DESC
```

This returns rooms sorted by most recent message, with the last message body and timestamp included. `NebRoom` is constructed from the joined result.

### Migration

New migration `v3_rooms_table` creates the `rooms` table. Existing tables unchanged.

## Room Changes

### RoomsProtocol gains roomListStream

```swift
public protocol RoomsProtocol: TypingProtocol {
    // existing methods...
    func roomListStream() -> AsyncStream<[NebRoom]>
}
```

### Room implementation

`roomListStream()` calls `database.roomListObservation()` which returns an `AsyncStream<[NebRoom]>` backed by GRDB `ValueObservation` on the `rooms` + `messages` tables.

Room no longer receives a `SyncProtocol` dependency. It still receives `roomListServiceProvider` for room subscription (needed by timeline sync and backfill).

## RoomListViewModel Changes

Currently:
```swift
init(syncService: any SyncProtocol, notificationService: ..., typingService: ...)
```

Becomes:
```swift
init(roomService: any RoomsProtocol, notificationService: ...)
```

- `syncService` replaced by `roomService` (which provides both room list and typing)
- `typingService` parameter removed -- `RoomsProtocol` inherits `TypingProtocol`
- Room list observation changes from `syncService.roomListStream()` to `roomService.roomListStream()`

## AppState Changes

```swift
// Before
let syncAdapter: MatrixSyncAdapter
roomListViewModel = RoomListViewModel(syncService: syncAdapter, ...)
syncAdapter.startSync()

// After
let sync: Sync
roomListViewModel = RoomListViewModel(roomService: roomAdapter, ...)
sync.start()
```

`AppState` still holds both `sync` and `roomAdapter`. It calls `sync.start()` on login and `sync.stop()` on logout. View models receive `roomAdapter` for room data.

## NebError

Currently defined in `MatrixSyncAdapter.swift`. Moves to `NebCore/Sources/NebCore/Models/NebError.swift`.

## Files Changed

| File | Change |
|------|--------|
| `NebCore/Sources/NebCore/Sync/MatrixSyncAdapter.swift` | Renamed to `Sync.swift`, rewritten to write to database, conform to new SyncProtocol |
| `NebCore/Sources/NebCore/Sync/SyncProtocol.swift` | Rewritten -- start/stop/isOnline/statusStream only |
| `NebCore/Sources/NebCore/Database/RoomRecord.swift` | New -- GRDB record for rooms table |
| `NebCore/Sources/NebCore/Database/NebDatabase.swift` | Add rooms table migration, upsertRoom, deleteRoom, roomListObservation |
| `NebCore/Sources/NebCore/Room/RoomsProtocol.swift` | Add roomListStream |
| `NebCore/Sources/NebCore/Room/Room.swift` | Implement roomListStream via database observation |
| `NebCore/Sources/NebCore/Models/NebError.swift` | New -- moved from MatrixSyncAdapter.swift |
| `Neb/AppState.swift` | Rename MatrixSyncAdapter to Sync, rewire RoomListViewModel |
| `Neb/ViewModels/RoomListViewModel.swift` | Replace SyncProtocol with RoomsProtocol, remove typingService param |
| `NebTests/Mocks/MockRoomService.swift` | Add roomListStream to MockRoomsService |
| `NebTests/Mocks/MockSyncService.swift` | Update to new SyncProtocol |
| `NebTests/RoomListViewModelTests.swift` | Update to use MockRoomsService instead of MockSyncService |

## Testing

### Database tests
- Insert and retrieve a room from rooms table.
- Upsert room updates existing row.
- Room list observation includes latest message from messages table.
- Room list sorted by most recent message timestamp.
- Rooms with no messages appear at the end.

### RoomListViewModel tests
- Receives rooms from roomService.roomListStream().
- Typing still works via roomService (inherits TypingProtocol).
- Unread counts, notifications unchanged.

## Edge Cases

- **Room removed from server**: Sync detects removal via the room list diff (`.remove`). Deletes the room from the rooms table. Room list observation updates automatically.
- **No messages in a room**: `lastMessage` and `lastMessageTimestamp` are nil. Room appears at the end of the list.
- **First launch**: rooms table is empty. Sync writes rooms as they arrive from the SDK. Room list populates progressively.
- **Offline**: `sync.isOnline` is false. Room list still loads instantly from the database.
