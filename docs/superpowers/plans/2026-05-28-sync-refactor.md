# Sync Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Sync a connection-only domain that writes room metadata to the database. Room reads the room list from the database. SyncProtocol loses roomListStream, RoomsProtocol gains it.

**Architecture:** Sync writes room metadata to a new `rooms` table in the database on every room list update from the SDK. Room observes the `rooms` table joined with latest message from `messages`. RoomListViewModel switches from SyncProtocol to RoomsProtocol.

**Tech Stack:** Swift 6.0, GRDB 7.0+, MatrixRustSDK, Swift Testing framework

**Spec:** `docs/superpowers/specs/2026-05-28-sync-refactor-design.md`

---

## File Structure

```
NebCore/Sources/NebCore/
├── Database/
│   ├── NebDatabase.swift         # Add v3 migration (rooms table), upsertRoom, deleteRoom, roomListObservation
│   └── RoomRecord.swift          # New -- GRDB record for rooms table
├── Sync/
│   ├── SyncProtocol.swift        # Rewrite -- start/stop/isOnline/statusStream only
│   └── Sync.swift                # Renamed from MatrixSyncAdapter.swift -- writes to database
├── Room/
│   ├── RoomsProtocol.swift       # Add roomListStream
│   └── Room.swift                # Implement roomListStream via database observation
├── Models/
│   └── NebError.swift            # New -- moved from MatrixSyncAdapter.swift

Neb/
├── AppState.swift                # Rename MatrixSyncAdapter to Sync, rewire RoomListViewModel
├── ViewModels/
│   └── RoomListViewModel.swift   # Replace SyncProtocol with RoomsProtocol

NebTests/
├── Mocks/
│   ├── MockRoomService.swift     # Add roomListStream + typing to MockRoomsService
│   └── MockSyncService.swift     # Update to new SyncProtocol (no roomListStream)
└── RoomListViewModelTests.swift  # Rewrite to use MockRoomsService
```

---

### Task 1: RoomRecord and Database Migration

Create the GRDB record for the rooms table and add the v3 migration.

**Files:**
- Create: `NebCore/Sources/NebCore/Database/RoomRecord.swift`
- Modify: `NebCore/Sources/NebCore/Database/NebDatabase.swift`
- Modify: `NebCore/Tests/NebCoreTests/NebDatabaseTests.swift`

- [ ] **Step 1: Write failing tests for room CRUD**

Add to `NebCore/Tests/NebCoreTests/NebDatabaseTests.swift`:

```swift
@Test func upsertAndFetchRoom() throws {
    let db = try NebDatabase()
    let room = RoomRecord(
        roomID: "!room:x", name: "Test Room", avatarURL: nil,
        unreadCount: 3, isDirect: false, directUserID: nil, memberCount: 5
    )
    try db.upsertRoom(room)
    let rooms = try db.fetchRooms()
    #expect(rooms.count == 1)
    #expect(rooms.first?.name == "Test Room")
    #expect(rooms.first?.unreadCount == 3)
}

@Test func upsertRoomUpdatesExisting() throws {
    let db = try NebDatabase()
    try db.upsertRoom(RoomRecord(
        roomID: "!room:x", name: "Old Name", unreadCount: 0,
        isDirect: false, memberCount: 2
    ))
    try db.upsertRoom(RoomRecord(
        roomID: "!room:x", name: "New Name", unreadCount: 5,
        isDirect: false, memberCount: 3
    ))
    let rooms = try db.fetchRooms()
    #expect(rooms.count == 1)
    #expect(rooms.first?.name == "New Name")
    #expect(rooms.first?.unreadCount == 5)
}

@Test func deleteRoom() throws {
    let db = try NebDatabase()
    try db.upsertRoom(RoomRecord(
        roomID: "!room:x", name: "Room", unreadCount: 0,
        isDirect: false, memberCount: 1
    ))
    try db.deleteRoom(roomID: "!room:x")
    let rooms = try db.fetchRooms()
    #expect(rooms.isEmpty)
}

@Test func roomListIncludesLastMessage() throws {
    let db = try NebDatabase()
    try db.upsertRoom(RoomRecord(
        roomID: "!room:x", name: "Room", unreadCount: 0,
        isDirect: false, memberCount: 2
    ))
    try db.insertMessage(MessageRecord(
        eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x",
        body: "Hello", timestamp: 1000
    ))
    try db.insertMessage(MessageRecord(
        eventID: "$evt2", roomID: "!room:x", senderID: "@bob:x",
        body: "World", timestamp: 2000
    ))
    let rooms = try db.fetchRoomList()
    #expect(rooms.count == 1)
    #expect(rooms.first?.lastMessage == "World")
    #expect(rooms.first?.lastMessageTimestamp == Date(timeIntervalSince1970: 2000))
}

@Test func roomListSortedByLatestMessage() throws {
    let db = try NebDatabase()
    try db.upsertRoom(RoomRecord(
        roomID: "!old:x", name: "Old Room", unreadCount: 0,
        isDirect: false, memberCount: 1
    ))
    try db.upsertRoom(RoomRecord(
        roomID: "!new:x", name: "New Room", unreadCount: 0,
        isDirect: false, memberCount: 1
    ))
    try db.insertMessage(MessageRecord(
        eventID: "$evt1", roomID: "!old:x", senderID: "@alice:x",
        body: "Old msg", timestamp: 1000
    ))
    try db.insertMessage(MessageRecord(
        eventID: "$evt2", roomID: "!new:x", senderID: "@alice:x",
        body: "New msg", timestamp: 2000
    ))
    let rooms = try db.fetchRoomList()
    #expect(rooms.first?.id == "!new:x")
    #expect(rooms.last?.id == "!old:x")
}

@Test func roomWithNoMessagesAppearsLast() throws {
    let db = try NebDatabase()
    try db.upsertRoom(RoomRecord(
        roomID: "!empty:x", name: "Empty", unreadCount: 0,
        isDirect: false, memberCount: 1
    ))
    try db.upsertRoom(RoomRecord(
        roomID: "!active:x", name: "Active", unreadCount: 0,
        isDirect: false, memberCount: 1
    ))
    try db.insertMessage(MessageRecord(
        eventID: "$evt1", roomID: "!active:x", senderID: "@alice:x",
        body: "Hello", timestamp: 1000
    ))
    let rooms = try db.fetchRoomList()
    #expect(rooms.first?.id == "!active:x")
    #expect(rooms.last?.id == "!empty:x")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd NebCore && swift test 2>&1 | tail -5`
Expected: FAIL -- `RoomRecord`, `upsertRoom`, `fetchRooms`, `fetchRoomList` don't exist

- [ ] **Step 3: Create RoomRecord**

Create `NebCore/Sources/NebCore/Database/RoomRecord.swift`:

```swift
import Foundation
import GRDB

public struct RoomRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "rooms"

    public var roomID: String
    public var name: String
    public var avatarURL: String?
    public var unreadCount: Int
    public var isDirect: Bool
    public var directUserID: String?
    public var memberCount: Int

    public init(
        roomID: String,
        name: String,
        avatarURL: String? = nil,
        unreadCount: Int = 0,
        isDirect: Bool = false,
        directUserID: String? = nil,
        memberCount: Int = 0
    ) {
        self.roomID = roomID
        self.name = name
        self.avatarURL = avatarURL
        self.unreadCount = unreadCount
        self.isDirect = isDirect
        self.directUserID = directUserID
        self.memberCount = memberCount
    }
}
```

- [ ] **Step 4: Add v3 migration and database methods**

In `NebDatabase.swift`, add the migration at the end of `migrate()`:

```swift
migrator.registerMigration("v3_rooms_table") { db in
    try db.create(table: "rooms") { t in
        t.column("roomID", .text).primaryKey()
        t.column("name", .text).notNull()
        t.column("avatarURL", .text)
        t.column("unreadCount", .integer).notNull().defaults(to: 0)
        t.column("isDirect", .boolean).notNull().defaults(to: false)
        t.column("directUserID", .text)
        t.column("memberCount", .integer).notNull().defaults(to: 0)
    }
}
```

Add methods to `NebDatabase`:

```swift
// MARK: - Rooms

public func upsertRoom(_ room: RoomRecord) throws {
    try dbQueue.write { db in
        try db.execute(
            sql: """
                INSERT OR REPLACE INTO rooms (roomID, name, avatarURL, unreadCount, isDirect, directUserID, memberCount)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [room.roomID, room.name, room.avatarURL, room.unreadCount,
                        room.isDirect, room.directUserID, room.memberCount]
        )
    }
}

public func deleteRoom(roomID: String) throws {
    try dbQueue.write { db in
        try db.execute(sql: "DELETE FROM rooms WHERE roomID = ?", arguments: [roomID])
    }
}

public func fetchRooms() throws -> [RoomRecord] {
    try dbQueue.read { db in
        try RoomRecord.fetchAll(db, sql: "SELECT * FROM rooms")
    }
}

/// Fetch room list with last message, sorted by most recent activity.
public func fetchRoomList() throws -> [NebRoom] {
    try dbQueue.read { db in
        let rows = try Row.fetchAll(db, sql: """
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
            """)
        return rows.map { row in
            let ts: Double? = row["lastMessageTimestamp"]
            return NebRoom(
                id: row["roomID"],
                name: row["name"],
                avatarURL: row["avatarURL"],
                lastMessage: row["lastMessage"],
                lastMessageTimestamp: ts.map { Date(timeIntervalSince1970: $0) },
                unreadCount: UInt(row["unreadCount"] as Int),
                isDirect: row["isDirect"],
                directUserID: row["directUserID"],
                memberCount: UInt(row["memberCount"] as Int)
            )
        }
    }
}

/// Observe room list reactively as an AsyncStream.
@MainActor
public func roomListObservation() -> AsyncStream<[NebRoom]> {
    AsyncStream { continuation in
        let observation = ValueObservation.tracking { db -> [NebRoom] in
            let rows = try Row.fetchAll(db, sql: """
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
                """)
            return rows.map { row in
                let ts: Double? = row["lastMessageTimestamp"]
                return NebRoom(
                    id: row["roomID"],
                    name: row["name"],
                    avatarURL: row["avatarURL"],
                    lastMessage: row["lastMessage"],
                    lastMessageTimestamp: ts.map { Date(timeIntervalSince1970: $0) },
                    unreadCount: UInt(row["unreadCount"] as Int),
                    isDirect: row["isDirect"],
                    directUserID: row["directUserID"],
                    memberCount: UInt(row["memberCount"] as Int)
                )
            }
        }
        let cancellable = observation.start(
            in: self.dbQueue,
            scheduling: .immediate,
            onError: { error in
                logger.error("roomListObservation error: \(error)")
                continuation.finish()
            },
            onChange: { rooms in
                continuation.yield(rooms)
            }
        )
        continuation.onTermination = { _ in
            cancellable.cancel()
        }
    }
}
```

- [ ] **Step 5: Run tests**

Run: `cd NebCore && swift test 2>&1 | grep -E "✔|✘" | head -30`
Expected: All new room tests pass, all existing tests still pass

- [ ] **Step 6: Commit**

```bash
git add NebCore/Sources/NebCore/Database/RoomRecord.swift \
       NebCore/Sources/NebCore/Database/NebDatabase.swift \
       NebCore/Tests/NebCoreTests/NebDatabaseTests.swift
git commit -m "feat(db): add rooms table with GRDB record and room list observation"
```

---

### Task 2: Move NebError and Rewrite SyncProtocol

Move `NebError` out of `MatrixSyncAdapter.swift` to its own file. Rewrite `SyncProtocol` to connection-only.

**Files:**
- Create: `NebCore/Sources/NebCore/Models/NebError.swift`
- Modify: `NebCore/Sources/NebCore/Sync/SyncProtocol.swift`
- Modify: `NebCore/Sources/NebCore/Sync/MatrixSyncAdapter.swift` (remove NebError from it)

- [ ] **Step 1: Create NebError.swift**

Create `NebCore/Sources/NebCore/Models/NebError.swift`:

```swift
import Foundation

public enum NebError: Error, LocalizedError {
    case notLoggedIn
    case roomNotFound(String)
    case recoveryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Not logged in"
        case .roomNotFound(let id): return "Room not found: \(id)"
        case .recoveryFailed(let message): return message
        }
    }
}
```

- [ ] **Step 2: Remove NebError from MatrixSyncAdapter.swift**

Delete the `NebError` enum (lines 180-192) from `NebCore/Sources/NebCore/Sync/MatrixSyncAdapter.swift`.

- [ ] **Step 3: Rewrite SyncProtocol**

Replace `NebCore/Sources/NebCore/Sync/SyncProtocol.swift`:

```swift
import Foundation

public protocol SyncProtocol: Sendable {
    func start() async throws
    func stop() async throws
    var isOnline: Bool { get }
    func statusStream() -> AsyncStream<Bool>
}
```

- [ ] **Step 4: Build NebCore**

Run: `cd NebCore && swift build 2>&1 | tail -5`
Expected: Compile errors in `MatrixSyncAdapter.swift` (doesn't conform to new SyncProtocol -- `startSync`/`stopSync` renamed, `roomListStream` removed). This is expected and will be fixed in Task 3.

- [ ] **Step 5: Commit**

```bash
git add NebCore/Sources/NebCore/Models/NebError.swift \
       NebCore/Sources/NebCore/Sync/SyncProtocol.swift \
       NebCore/Sources/NebCore/Sync/MatrixSyncAdapter.swift
git commit -m "refactor: move NebError to Models, rewrite SyncProtocol to connection-only"
```

---

### Task 3: Rewrite Sync Adapter

Rename `MatrixSyncAdapter` to `Sync`. Rewrite to conform to new `SyncProtocol` (start/stop/isOnline/statusStream). Replace `convertAndEmit` with database writes. Remove room list continuations.

**Files:**
- Rename: `NebCore/Sources/NebCore/Sync/MatrixSyncAdapter.swift` → `NebCore/Sources/NebCore/Sync/Sync.swift`

- [ ] **Step 1: Rename file and rewrite class**

Delete `MatrixSyncAdapter.swift` and create `Sync.swift`. The new implementation:

- Class named `Sync`, conforms to `SyncProtocol`
- `start()` replaces `startSync()`: starts SDK SyncService, sets up room list listener
- `stop()` replaces `stopSync()`: stops SDK SyncService
- `isOnline`: tracks whether sync is running
- `statusStream()`: emits connection status changes
- `roomListService`: still exposed publicly (not via protocol) for Room and BackfillWorker
- `applyUpdates()`: same diff logic, but calls `convertAndWriteToDatabase()` instead of `convertAndEmit()`
- `convertAndWriteToDatabase()`: for each SDK room, fetches `roomInfo()`, builds `RoomRecord`, calls `database.upsertRoom()`. Also handles room removals via `database.deleteRoom()`.
- No more `continuations`, `latestNebRooms`, or `emitWorkItem` -- the database is the cache, GRDB observation handles change notification.

Key changes from the current `MatrixSyncAdapter`:
- Remove all `AsyncStream` continuation management
- Remove `roomListStream()` method
- Add `isOnline` property and `statusStream()` 
- `convertAndEmit()` → `convertAndWriteToDatabase()` which calls `database.upsertRoom()` per room
- Constructor gains `database: NebDatabase` parameter
- Track room removals: maintain a `Set<String>` of known room IDs. On each update, compare with new set. Rooms that disappeared get `database.deleteRoom()`.

The debounced dispatch pattern (100ms) should stay -- it prevents thrashing on rapid SDK diff callbacks. But instead of emitting to continuations, the debounced block writes to the database.

- [ ] **Step 2: Build NebCore**

Run: `cd NebCore && swift build 2>&1 | tail -10`
Expected: Errors in AppState (references `MatrixSyncAdapter`). NebCore itself should compile.

- [ ] **Step 3: Commit**

```bash
git add NebCore/Sources/NebCore/Sync/
git commit -m "refactor: rename MatrixSyncAdapter to Sync, write room list to database"
```

---

### Task 4: Add roomListStream to RoomsProtocol and Room

Move `roomListStream()` to `RoomsProtocol`. Implement it in `Room` via database observation.

**Files:**
- Modify: `NebCore/Sources/NebCore/Room/RoomsProtocol.swift`
- Modify: `NebCore/Sources/NebCore/Room/Room.swift`

- [ ] **Step 1: Add roomListStream to RoomsProtocol**

In `RoomsProtocol.swift`, add to the protocol:

```swift
func roomListStream() -> AsyncStream<[NebRoom]>
```

- [ ] **Step 2: Implement in Room**

In `Room.swift`, add the implementation. Room already has a `database` property:

```swift
public func roomListStream() -> AsyncStream<[NebRoom]> {
    database.roomListObservation()
}
```

- [ ] **Step 3: Build NebCore**

Run: `cd NebCore && swift build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (Room already conforms to RoomsProtocol, new method added)

- [ ] **Step 4: Commit**

```bash
git add NebCore/Sources/NebCore/Room/RoomsProtocol.swift \
       NebCore/Sources/NebCore/Room/Room.swift
git commit -m "feat(room): add roomListStream to RoomsProtocol, backed by database observation"
```

---

### Task 5: Rewire AppState and RoomListViewModel

Update AppState to use `Sync` instead of `MatrixSyncAdapter`. Update RoomListViewModel to receive `RoomsProtocol` instead of `SyncProtocol`.

**Files:**
- Modify: `Neb/AppState.swift`
- Modify: `Neb/ViewModels/RoomListViewModel.swift`
- Modify: `NebTests/Mocks/MockRoomService.swift`
- Modify: `NebTests/Mocks/MockSyncService.swift`
- Modify: `NebTests/RoomListViewModelTests.swift`

- [ ] **Step 1: Update AppState**

Changes:
- `let syncAdapter: MatrixSyncAdapter` → `let sync: Sync`
- Construction: `let sync = Sync(clientProvider: { session.getClient() }, database: database)`
- Room adapter: `let room = Room(clientProvider: { session.getClient() }, roomListServiceProvider: { sync.roomListService }, database: database)`
- BackfillWorker: `roomListServiceProvider: { sync.roomListService }`
- RoomListViewModel: `RoomListViewModel(roomService: roomAdapter, notificationService: notificationAdapter)` -- no more `typingService` param (RoomsProtocol inherits TypingProtocol)
- `onLoggedIn()`: `sync.start()` instead of `syncAdapter.startSync()`
- `onLoggedOut()`: `sync.stop()` instead of `syncAdapter.stopSync()`
- Remove `makeTypingService()` -- typing comes from roomAdapter via RoomsProtocol
- BackfillWorker start: still waits for first room list emission, but from `roomAdapter.roomListStream()` instead of `syncAdapter.roomListStream()`

- [ ] **Step 2: Update RoomListViewModel**

Changes:
- Replace `syncService: any SyncProtocol` with `roomService: any RoomsProtocol`
- Remove `typingService: (any TypingProtocol)?` param -- `RoomsProtocol` inherits `TypingProtocol`
- `startObserving()`: `roomService.roomListStream()` instead of `syncService.roomListStream()`
- `updateTypingSubscriptions()`: use `roomService` instead of `typingService`

- [ ] **Step 3: Update MockRoomsService**

Add `roomListStream`, `sendTypingNotice`, `typingUsersStream` to `MockRoomsService`:

```swift
final class MockRoomsService: RoomsProtocol, @unchecked Sendable {
    var createdDMUserID: String?
    var rooms: [NebRoom] = []
    private var roomsContinuation: AsyncStream<[NebRoom]>.Continuation?
    var typingNotices: [(roomID: String, isTyping: Bool)] = []
    private var typingContinuations: [String: AsyncStream<[NebUser]>.Continuation] = [:]

    func roomListStream() -> AsyncStream<[NebRoom]> {
        AsyncStream { continuation in
            self.roomsContinuation = continuation
            continuation.yield(self.rooms)
        }
    }

    func emitRooms(_ rooms: [NebRoom]) {
        self.rooms = rooms
        roomsContinuation?.yield(rooms)
    }

    func sendTypingNotice(roomID: String, isTyping: Bool) async throws {
        typingNotices.append((roomID: roomID, isTyping: isTyping))
    }

    func typingUsersStream(roomID: String) -> AsyncStream<[NebUser]> {
        AsyncStream { continuation in
            self.typingContinuations[roomID] = continuation
            continuation.yield([])
        }
    }

    func emitTypingUsers(roomID: String, users: [NebUser]) {
        typingContinuations[roomID]?.yield(users)
    }

    // existing room operation methods stay the same...
    func createRoom(name: String?, topic: String?, isEncrypted: Bool, isDirect: Bool, inviteUserIDs: [String]) async throws -> String { "!new-room:example.com" }
    func createDM(userID: String) async throws -> String {
        createdDMUserID = userID
        return "!new-dm-room:example.com"
    }
    func joinRoom(roomIDOrAlias: String) async throws {}
    func leaveRoom(roomID: String) async throws {}
    func setRoomName(roomID: String, name: String) async throws {}
    func setRoomTopic(roomID: String, topic: String) async throws {}
    func setRoomAvatar(roomID: String, data: Data, mimeType: String) async throws {}
    func roomInfo(roomID: String) async throws -> NebRoom { NebRoom(id: roomID, name: "Mock Room") }
}
```

- [ ] **Step 4: Update MockSyncService**

Replace to match new SyncProtocol:

```swift
final class MockSyncService: SyncProtocol, @unchecked Sendable {
    var isOnline: Bool = false
    var started = false
    var stopped = false

    func start() async throws {
        started = true
        isOnline = true
    }

    func stop() async throws {
        stopped = true
        isOnline = false
    }

    func statusStream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.yield(self.isOnline)
        }
    }
}
```

- [ ] **Step 5: Update RoomListViewModelTests**

Replace `MockSyncService` with `MockRoomsService` throughout. Replace `syncService:` param with `roomService:`. For typing tests, use `MockRoomsService` directly (no separate `typingService` param):

Every test that currently does:
```swift
let syncService = MockSyncService()
let vm = await RoomListViewModel(syncService: syncService)
syncService.emitRooms([...])
```

Becomes:
```swift
let roomService = MockRoomsService()
let vm = await RoomListViewModel(roomService: roomService)
roomService.emitRooms([...])
```

For typing tests that currently use both `MockSyncService` and `MockTypingService`:
```swift
let syncService = MockSyncService()
let typingService = MockTypingService()
let vm = await RoomListViewModel(syncService: syncService, typingService: typingService)
```

Becomes:
```swift
let roomService = MockRoomsService()
let vm = await RoomListViewModel(roomService: roomService)
```

And `typingService.emitTypingUsers(...)` becomes `roomService.emitTypingUsers(...)`.

- [ ] **Step 6: Update MainView and NebApp**

In `MainView.swift`, check for any `typingServiceProvider` references that need updating. In `NebApp.swift`, check for `makeTypingService()` calls.

The `typingServiceProvider` in MainView is used for `TimelineViewModel` construction -- that still takes a separate `TypingProtocol`. AppState provides it via `roomAdapter` (which conforms to `RoomsProtocol` which inherits `TypingProtocol`).

- [ ] **Step 7: Build and test**

Run: `xcodegen generate && xcodebuild -project Neb.xcodeproj -scheme Neb build CODE_SIGNING_ALLOWED=NO 2>&1 | grep "error:" | grep -v VerificationViewModel`
Expected: No errors

Run: `cd NebCore && swift test 2>&1 | grep -E "✔|✘" | head -30`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: rewire RoomListViewModel to RoomsProtocol, Sync is connection-only"
```

---

### Task 6: Cleanup and Final Verification

Remove any remaining references to old types. Verify everything builds and tests pass.

**Files:**
- Various cleanup

- [ ] **Step 1: Check for stale references**

Run: `grep -r "MatrixSyncAdapter\|startSync\|stopSync\|syncAdapter" NebCore/Sources/ Neb/ NebTests/ --include="*.swift" | grep -v ".build/"`

Fix any remaining references.

- [ ] **Step 2: Check MockTypingService is still needed**

If `MockTypingService` is only used in `TimelineViewModelTests` (for `TimelineViewModel` which still takes a separate `typingService` param), keep it. If nothing uses it, delete it.

- [ ] **Step 3: Build everything**

Run: `cd NebCore && swift build && swift test 2>&1 | grep -E "✔|✘|Build complete"`

Run: `xcodegen generate && xcodebuild -project Neb.xcodeproj -scheme Neb build CODE_SIGNING_ALLOWED=NO 2>&1 | grep "error:" | grep -v VerificationViewModel`

Expected: All builds succeed, all tests pass

- [ ] **Step 4: Commit if any changes**

```bash
git add -A
git commit -m "cleanup: remove stale sync references"
```
