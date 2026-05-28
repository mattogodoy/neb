# Local Message Database -- Full Conversation Store with Background Backfill

## Problem

The SDK's event cache is a thin sliding window -- sliding sync keeps ~10 items per room, plus whatever the user has scrolled into view. There is no full local conversation history. This means:

- Search can only cover messages the SDK has seen during this device's lifetime.
- Opening a room requires the SDK to fetch from the server.
- The experience is worse than Telegram, which renders everything from a local database instantly.

## Goal

Store the full conversation history in Neb's local database (GRDB/SQLCipher). The UI reads from the database, not the SDK's timeline API. The SDK becomes the sync/network layer that feeds the database. Background backfill paginates backwards from the server to fill in history. The result is instant room loads, full offline access, and complete local search.

## Architecture

```
User action (send) ──→ Write pending to DB ──→ Forward to SDK send queue
                              ↓
SDK sync stream ──→ Writer ──→ GRDB/SQLCipher ──→ GRDB ValueObservation ──→ ViewModel ──→ View
                                    ↑
Backfill worker ──→ SDK paginate ───┘
```

Three write paths into the database:

1. **Live sync**: the SDK timeline listener converts events and writes them to the database. Replaces the current pattern of yielding `[NebMessage]` via `AsyncStream`.
2. **User sends**: a pending row is written to the database immediately (local echo). The message is forwarded to the SDK send queue. When the SDK confirms via sync, the row is updated with the real event ID and "sent" status.
3. **Backfill worker**: runs in the background after sync starts. Iterates rooms, paginates backwards from the server, writes historical messages to the database.

One read path:

- **GRDB `ValueObservation`**: view models observe queries like `SELECT ... FROM messages WHERE roomID = ? ORDER BY timestamp`. When the database changes (from any write path), the UI updates reactively.

## Database Schema

Normalized (option A -- store raw data, derive at read time). Encrypted with SQLCipher, passphrase from Keychain (per ADR-0001).

### `messages`

The core table. One row per message event.

| Column | Type | Notes |
|--------|------|-------|
| `eventID` | TEXT | Primary key. For pending sends, a client-generated transaction ID (prefixed `~` to distinguish from server event IDs). Replaced with real event ID on confirmation. |
| `roomID` | TEXT | NOT NULL, indexed. Foreign key to the room. |
| `senderID` | TEXT | NOT NULL. Matrix user ID. |
| `body` | TEXT | NOT NULL. Plain text body. |
| `formattedBody` | TEXT | Nullable. HTML formatted body (for rich text). |
| `timestamp` | REAL | NOT NULL, indexed. Unix epoch seconds (TimeInterval). |
| `isEdited` | INTEGER | NOT NULL, default 0. Boolean. |
| `sendStatus` | TEXT | NOT NULL, default 'sent'. One of: 'pending', 'sending', 'sent', 'failed'. |
| `transactionID` | TEXT | Nullable, indexed. The client-generated transaction ID for local echo reconciliation. Cleared after confirmation. |

Index: `(roomID, timestamp)` for paginated timeline queries.
Index: `transactionID` for matching SDK confirmations to pending rows.

### `reactions`

One row per user per emoji per event.

| Column | Type | Notes |
|--------|------|-------|
| `eventID` | TEXT | NOT NULL. References `messages.eventID`. |
| `emoji` | TEXT | NOT NULL. The reaction key. |
| `senderID` | TEXT | NOT NULL. Who reacted. |

Primary key: `(eventID, emoji, senderID)`.
Index: `eventID` for joins.

### `read_receipts`

Latest read position per user per room.

| Column | Type | Notes |
|--------|------|-------|
| `roomID` | TEXT | NOT NULL. |
| `userID` | TEXT | NOT NULL. |
| `eventID` | TEXT | NOT NULL. The last-read event. |

Primary key: `(roomID, userID)`.

### `profiles`

Cached display names and avatars. Updated as the sync stream provides profile data.

| Column | Type | Notes |
|--------|------|-------|
| `userID` | TEXT | Primary key. |
| `displayName` | TEXT | Nullable. |
| `avatarURL` | TEXT | Nullable. MXC URI. |

### `search_fts`

FTS5 external content table on `messages.body`. Same as the current design, but now the content table is `messages` instead of the old `search_index`.

```sql
CREATE VIRTUAL TABLE search_fts USING fts5(
    body,
    content='messages',
    content_rowid='rowid'
);
```

Triggers keep FTS in sync with `messages` (insert, update, delete) -- same pattern as the current `search_index` triggers.

### `backfill_state`

Per-room progress tracking for the backfill worker.

| Column | Type | Notes |
|--------|------|-------|
| `roomID` | TEXT | Primary key. |
| `oldestEventID` | TEXT | The oldest event ID we've stored for this room. |
| `oldestTimestamp` | REAL | Timestamp of the oldest event. For ordering/debugging. |
| `reachedStart` | INTEGER | NOT NULL, default 0. Boolean. True if we've paginated to the beginning of the room. |

Note: the SDK does not expose pagination tokens through the Swift bindings. Pagination state is internal to the SDK's timeline object. The backfill worker resumes by creating a new timeline for the room and paginating backwards until it encounters events already in the database (deduplicated via `INSERT OR IGNORE`). This means some overlap on resume, but it's correct and simple.

### Migration from current schema

The current `search_index` and `search_fts` tables are dropped. The `dm_assignments` table is unchanged. A new migration creates all the tables above.

## Live Sync Writer

Replaces the current `NebTimelineListener` → `AsyncStream` → `ViewModel` flow.

The `Room` adapter's timeline listener still receives SDK diffs (`onUpdate(diff:)`), still converts `TimelineItem` → message data, but instead of yielding to a continuation, it writes to the database:

- **Append/PushBack**: `INSERT OR IGNORE` into `messages`. Ignore because backfill may have already stored the event.
- **Set (update)**: `UPDATE messages SET ... WHERE eventID = ?`. Handles edits, decryption updates, send status changes.
- **Remove**: `UPDATE messages SET body = '[redacted]', formattedBody = NULL WHERE eventID = ?`. We keep the row for timeline continuity but clear the content.
- **Clear/Reset**: these are SDK-internal operations (e.g., timeline mode change). We don't delete from the database -- our data is persistent. We can ignore these or treat them as a signal to re-query.

Profile data from the SDK's `senderProfile` is written to the `profiles` table.
Reactions from `msgLike.reactions` are written to the `reactions` table (delete + reinsert per event, since the SDK gives us the full reaction state).
Read receipts are written to `read_receipts`.

### Reconciling local echo

When the user sends a message:

1. Generate a transaction ID (e.g., `~send-{UUID}`).
2. Insert into `messages` with `sendStatus = 'pending'`, `eventID = transactionID`, `transactionID = transactionID`.
3. The UI sees it immediately via `ValueObservation`.
4. Forward to SDK: `timeline.send(msg:)`.
5. SDK processes the send. The sync stream delivers the confirmed event with a real event ID.
6. The writer matches the confirmation to the pending row via `transactionID` (the SDK's `localSendState` provides this).
7. Update the row: set `eventID` to the real event ID, `sendStatus = 'sent'`, clear `transactionID`.

If the SDK reports a send failure, update `sendStatus = 'failed'`.

On app launch, any rows with `sendStatus = 'pending'` or `sendStatus = 'sending'` are checked against the SDK's send queue. If the SDK doesn't have them queued, they're marked `'failed'` so the user can retry or dismiss.

## Backfill Worker

A background task that runs after sync starts. Its job is to fill in historical messages that the SDK hasn't synced to this device.

### Lifecycle

1. Triggered by `AppState.onLoggedIn()` after `syncAdapter.startSync()`.
2. Gets the list of joined rooms from the sync adapter.
3. For each room (ordered by most recent activity first):
   a. Check `backfill_state` -- if `reachedStart` is true, skip.
   b. Subscribe to the room (required by the SDK before timeline operations).
   c. Create a timeline, attach a listener that writes to the database.
   d. Paginate backwards in batches of 50.
   e. After each batch, update `backfill_state` with the new oldest event and token.
   f. If the SDK reports "reached start of timeline", set `reachedStart = true`.
   g. Yield between batches (`Task.yield()`) to avoid blocking.
4. After all rooms are processed, the worker sleeps. When new rooms appear (via the room list stream), it processes them.

### Throttling

- One room at a time (sequential, not parallel).
- `Task.yield()` between batches to let other work run.
- Low priority: use `Task(priority: .utility)`.
- If the user opens a room, that room's backfill should be prioritized (moved to the front of the queue).

### Resume

On next app launch, the worker checks `backfill_state` for each room:
- `reachedStart = true`: skip entirely.
- `reachedStart = false`: create a new timeline, paginate backwards. Events already in the database are deduplicated via `INSERT OR IGNORE`. The worker stops when it encounters a full batch of already-known events (all inserts ignored), meaning it's caught up to where it left off.
- No entry: start from the newest event and paginate backwards.

### Deduplication

Messages from backfill may overlap with messages from live sync. `INSERT OR IGNORE` on the `eventID` primary key handles this -- if the event already exists, the backfill write is silently dropped.

## View Model Changes

### TimelineViewModel

Currently holds `[NebMessage]` in memory, populated by an `AsyncStream` from the `Room` adapter.

New approach:
- Observes `messages` + `profiles` + `reactions` via GRDB `ValueObservation`.
- Query: messages for the room, joined with profiles for sender info, ordered by timestamp.
- Pagination: load a window (e.g., newest 50), expand on scroll. Database pagination, not SDK pagination.
- `isOutgoing` derived at read time: `message.senderID == currentUserID`.
- `isEditable` derived at read time: `message.senderID == currentUserID && message.sendStatus == 'sent'`.
- Read receipts and reactions fetched per-message from their tables.

### RoomListViewModel

Currently receives `[NebRoom]` from the sync adapter's `roomListStream()`.

The sync adapter still provides room metadata (name, avatar, member count, isDirect). For last message preview and timestamp, the view model can query the database: `SELECT body, timestamp FROM messages WHERE roomID = ? ORDER BY timestamp DESC LIMIT 1`.

Or: the room list stream continues to provide everything, and the database is only used for the timeline view. This is simpler and avoids making the room list dependent on the database.

Recommendation: keep the room list reading from the sync adapter for now. The timeline view reads from the database. This minimizes the blast radius of the change.

## Protocol Changes

### TimelineProtocol

The current protocol returns `AsyncStream<[NebMessage]>`. With database-backed rendering, the view model observes the database directly. The protocol shifts to write-oriented:

```swift
public protocol TimelineProtocol: Sendable {
    /// Start syncing a room's timeline to the database.
    func startTimelineSync(roomID: String) async throws
    /// Stop syncing a room's timeline.
    func stopTimelineSync(roomID: String) async throws
    /// Send a message (writes pending row to DB, forwards to SDK).
    func send(roomID: String, body: String) async throws
    func sendReply(roomID: String, body: String, replyToEventID: String) async throws
    func edit(roomID: String, eventID: String, newBody: String) async throws
    func delete(roomID: String, eventID: String, reason: String?) async throws
    func react(roomID: String, eventID: String, emoji: String) async throws
    func markAsRead(roomID: String) async throws
    func sendImage(roomID: String, url: URL, caption: String?) async throws
    func sendFile(roomID: String, url: URL, caption: String?) async throws
    func sendVideo(roomID: String, url: URL, thumbnailURL: URL, caption: String?) async throws
}
```

`messageStream(roomID:)` is removed. `paginateBackwards(roomID:count:)` is removed (the backfill worker handles this, or the view model queries deeper into the database).

`startTimelineSync` / `stopTimelineSync` replace the implicit lifecycle of `messageStream`. When the user opens a room, the view model calls `startTimelineSync` to activate the SDK timeline listener that writes to the database. When the user leaves the room, `stopTimelineSync` detaches the listener.

### SearchProtocol

Unchanged. `search(query:roomID:)` still returns `[SearchResult]`. The implementation switches from querying `search_index` to querying `search_fts` backed by `messages`.

### NebDatabase (expanded)

`NebDatabase` gains write methods for adapters and observation methods for view models. It's not behind a protocol -- it's a concrete class shared by adapters and view models via dependency injection.

Write methods (used by adapters and backfill worker):

```swift
func insertMessage(_ message: MessageRecord) throws
func updateMessage(eventID: String, updates: MessageUpdate) throws
func reconcilePendingMessage(transactionID: String, confirmedEventID: String) throws
func insertReactions(eventID: String, reactions: [ReactionRecord]) throws
func updateReadReceipt(roomID: String, userID: String, eventID: String) throws
func upsertProfile(userID: String, displayName: String?, avatarURL: String?) throws
func backfillState(roomID: String) throws -> BackfillState?
func updateBackfillState(_ state: BackfillState) throws
```

Observation methods (used by view models):

```swift
func messagesObservation(roomID: String, limit: Int) -> ValueObservation<[MessageWithProfile]>
func reactionsObservation(eventIDs: [String]) -> ValueObservation<[ReactionRecord]>
func readReceiptsObservation(roomID: String) -> ValueObservation<[ReadReceiptRecord]>
```

`MessageWithProfile` is a joined result type: `MessageRecord` + `ProfileRecord` fields, returned from a `SELECT messages.*, profiles.displayName, profiles.avatarURL FROM messages LEFT JOIN profiles ON messages.senderID = profiles.userID` query.

Search (used by `Room` to implement `SearchProtocol`):

```swift
func searchMessages(query: String, roomID: String?) throws -> [SearchResult]
```

### View model database access

The `TimelineViewModel` receives `NebDatabase` via init, alongside the existing protocol dependencies. `NebDatabase` is injected by `AppState` when creating the view model. In tests, an in-memory `NebDatabase` instance is used (the existing `NebDatabase()` initializer already supports this).

## Backfill Worker Placement

The backfill worker is not a domain concept. It's infrastructure -- a background process that populates the database. It lives alongside the sync machinery, not in a domain folder.

For now, it can be a class in `Room/` (since it uses the SDK's room/timeline APIs) or a standalone file. The folder restructure (separating adapters from domain protocols) is a separate task.

## NebMessage Model

`NebMessage` remains the view-layer model. It's no longer created by the timeline listener directly -- it's assembled from database rows + derived fields.

A new internal `MessageRecord` struct represents the database row:

```swift
struct MessageRecord: Codable, FetchableRecord, PersistableRecord {
    var eventID: String
    var roomID: String
    var senderID: String
    var body: String
    var formattedBody: String?
    var timestamp: TimeInterval
    var isEdited: Bool
    var sendStatus: String
    var transactionID: String?
}
```

The view model maps `MessageRecord` + `ProfileRecord` + reactions + read receipts → `NebMessage`, adding derived fields like `isOutgoing`, `isEditable`, `isEmojiOnly`.

## Files Changed

| File | Change |
|------|--------|
| `NebCore/Sources/NebCore/Database/NebDatabase.swift` | Rewrite -- new schema, new methods, ValueObservation queries |
| `NebCore/Sources/NebCore/Database/MessageRecord.swift` | New -- GRDB record for messages table |
| `NebCore/Sources/NebCore/Database/ReactionRecord.swift` | New -- GRDB record for reactions table |
| `NebCore/Sources/NebCore/Database/ProfileRecord.swift` | New -- GRDB record for profiles table |
| `NebCore/Sources/NebCore/Database/BackfillState.swift` | New -- GRDB record for backfill tracking |
| `NebCore/Sources/NebCore/Room/Room.swift` | Rewrite timeline listener to write to DB instead of AsyncStream |
| `NebCore/Sources/NebCore/Room/TimelineProtocol.swift` | Replace messageStream with startTimelineSync/stopTimelineSync |
| `NebCore/Sources/NebCore/Room/BackfillWorker.swift` | New -- background backfill task |
| `NebCore/Sources/NebCore/Room/SearchProtocol.swift` | Unchanged (implementation changes in Room.swift) |
| `NebCore/Sources/NebCore/Models/NebMessage.swift` | Unchanged (still the view-layer model) |
| `NebCore/Sources/NebCore/ViewModels/TimelineViewModel.swift` | Rewrite -- observe database instead of AsyncStream |
| `Neb/AppState.swift` | Wire database, start backfill worker after sync |

## Testing

### Database tests (NebDatabaseTests)
- Insert and retrieve a message.
- Insert duplicate eventID is ignored.
- Update message (edit, send status change).
- Reactions: insert, replace, query per event.
- Read receipts: upsert, query per room.
- Profiles: upsert, query.
- FTS5 search returns matching messages.
- Backfill state: save, load, reachedStart flag.
- Migration from old schema drops search_index, creates new tables.

### Backfill worker tests (BackfillWorkerTests)
- Processes rooms in order of recent activity.
- Skips rooms where reachedStart is true.
- Resumes by deduplicating against existing messages.
- Writes messages to database.
- Updates backfill state after each batch.
- Deduplication: backfill doesn't overwrite existing messages.

### Timeline integration tests
- Live sync writes messages to database.
- Send creates pending row, confirmation updates it.
- Send failure updates status to 'failed'.
- Redaction clears body but keeps row.
- ValueObservation delivers updates to the view model.

### Existing tests
- `TimelineViewModelTests` need rewriting to use mock database instead of mock AsyncStream.
- `RoomListViewModelTests` unchanged (room list still reads from sync adapter).

## Edge Cases

- **App killed during backfill**: resumes from `backfill_state` on next launch. No data loss.
- **App killed with pending sends**: on next launch, reconcile pending rows with SDK send queue.
- **Encrypted rooms**: the SDK decrypts events before the timeline listener sees them. The database stores decrypted content. If decryption fails (UTD), the body is stored as a placeholder. When the SDK later decrypts the event (key arrives via sync), the timeline listener update writes the decrypted content to the database.
- **Room with no messages**: backfill finishes immediately, sets reachedStart = true.
- **Extremely large rooms**: backfill may take a long time. The worker is low-priority and yields frequently. The UI works with whatever is in the database already.
- **Database corruption**: SQLCipher + GRDB handle crash safety. If corruption occurs, the database can be rebuilt from scratch by clearing `backfill_state` and re-running the backfill worker.
- **Multiple devices**: each device has its own database. Backfill runs independently per device.

## What This Doesn't Cover

- **Media storage**: media (images, files, videos) are not stored in the database. The SDK's media cache handles this. Future work.
- **Room metadata in the database**: room name, avatar, member count stay in the SDK. The room list reads from the sync adapter. Future work may move this to the database too.
- **Folder restructure**: separating adapters from domain protocols is a separate task.
- **Adapter renames**: renaming MatrixSyncAdapter, MatrixTypingAdapter, MatrixNotificationAdapter is a separate task.
- **DM assignment rule**: persisting DM assignments in the database is a separate task (already designed).
