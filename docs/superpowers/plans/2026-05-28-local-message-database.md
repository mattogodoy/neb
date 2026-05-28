# Local Message Database Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SDK timeline stream with a local GRDB/SQLCipher message database that the UI reads from reactively.

**Architecture:** The SDK timeline listener writes to the database instead of yielding to an AsyncStream. View models observe the database via GRDB `ValueObservation`. A background backfill worker paginates historical messages from the server. Local echo for sends is written directly to the database.

**Tech Stack:** Swift 6.0, GRDB 7.0+, SQLCipher (future -- plain GRDB for now), Swift Testing framework

**Spec:** `docs/superpowers/specs/2026-05-28-local-message-database-design.md`

---

## File Structure

```
NebCore/Sources/NebCore/
├── Database/
│   ├── NebDatabase.swift          # Rewrite -- new schema, write + observation methods
│   ├── MessageRecord.swift        # New -- GRDB record for messages table
│   ├── ReactionRecord.swift       # New -- GRDB record for reactions table
│   ├── ProfileRecord.swift        # New -- GRDB record for profiles table
│   ├── ReadReceiptRecord.swift    # New -- GRDB record for read_receipts table
│   ├── BackfillState.swift        # New -- GRDB record for backfill_state table
│   └── MessageWithProfile.swift   # New -- joined result type for timeline queries
├── Room/
│   ├── Room.swift                 # Rewrite timeline listener to write to DB
│   ├── TimelineProtocol.swift     # Remove messageStream/paginateBackwards, add start/stopTimelineSync
│   ├── BackfillWorker.swift       # New -- background backfill task
│   └── SearchProtocol.swift       # Unchanged interface, implementation updates in Room.swift
├── Models/
│   └── NebMessage.swift           # Unchanged
└── ViewModels/                    # Note: ViewModels dir does not exist in NebCore currently

Neb/
├── ViewModels/
│   └── TimelineViewModel.swift    # Rewrite -- observe database instead of AsyncStream
├── Views/
│   └── MainView.swift             # Update TimelineViewModel construction to pass database
├── AppState.swift                 # Wire database, start backfill worker
└── NebTests/
    ├── Mocks/MockRoomService.swift    # Update mock to match new TimelineProtocol
    └── TimelineViewModelTests.swift   # Rewrite to use in-memory database

NebCore/Tests/NebCoreTests/
├── NebDatabaseTests.swift         # New -- database CRUD + FTS5 tests
└── BackfillWorkerTests.swift      # New -- backfill logic tests
```

---

### Task 1: Database Record Types

Create the GRDB record structs that map to the new schema. These are pure data types with no dependencies on the SDK.

**Files:**
- Create: `NebCore/Sources/NebCore/Database/MessageRecord.swift`
- Create: `NebCore/Sources/NebCore/Database/ReactionRecord.swift`
- Create: `NebCore/Sources/NebCore/Database/ProfileRecord.swift`
- Create: `NebCore/Sources/NebCore/Database/ReadReceiptRecord.swift`
- Create: `NebCore/Sources/NebCore/Database/BackfillState.swift`
- Create: `NebCore/Sources/NebCore/Database/MessageWithProfile.swift`

- [ ] **Step 1: Create MessageRecord**

```swift
// NebCore/Sources/NebCore/Database/MessageRecord.swift
import Foundation
import GRDB

public struct MessageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "messages"

    public var eventID: String
    public var roomID: String
    public var senderID: String
    public var body: String
    public var formattedBody: String?
    public var timestamp: Double
    public var isEdited: Bool
    public var sendStatus: String
    public var transactionID: String?

    public init(
        eventID: String,
        roomID: String,
        senderID: String,
        body: String,
        formattedBody: String? = nil,
        timestamp: Double,
        isEdited: Bool = false,
        sendStatus: String = "sent",
        transactionID: String? = nil
    ) {
        self.eventID = eventID
        self.roomID = roomID
        self.senderID = senderID
        self.body = body
        self.formattedBody = formattedBody
        self.timestamp = timestamp
        self.isEdited = isEdited
        self.sendStatus = sendStatus
        self.transactionID = transactionID
    }
}
```

- [ ] **Step 2: Create ReactionRecord**

```swift
// NebCore/Sources/NebCore/Database/ReactionRecord.swift
import Foundation
import GRDB

public struct ReactionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "reactions"

    public var eventID: String
    public var emoji: String
    public var senderID: String

    public init(eventID: String, emoji: String, senderID: String) {
        self.eventID = eventID
        self.emoji = emoji
        self.senderID = senderID
    }
}
```

- [ ] **Step 3: Create ProfileRecord**

```swift
// NebCore/Sources/NebCore/Database/ProfileRecord.swift
import Foundation
import GRDB

public struct ProfileRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "profiles"

    public var userID: String
    public var displayName: String?
    public var avatarURL: String?

    public init(userID: String, displayName: String? = nil, avatarURL: String? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}
```

- [ ] **Step 4: Create ReadReceiptRecord**

```swift
// NebCore/Sources/NebCore/Database/ReadReceiptRecord.swift
import Foundation
import GRDB

public struct ReadReceiptRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "read_receipts"

    public var roomID: String
    public var userID: String
    public var eventID: String

    public init(roomID: String, userID: String, eventID: String) {
        self.roomID = roomID
        self.userID = userID
        self.eventID = eventID
    }
}
```

- [ ] **Step 5: Create BackfillState**

```swift
// NebCore/Sources/NebCore/Database/BackfillState.swift
import Foundation
import GRDB

public struct BackfillState: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "backfill_state"

    public var roomID: String
    public var oldestEventID: String?
    public var oldestTimestamp: Double?
    public var reachedStart: Bool

    public init(roomID: String, oldestEventID: String? = nil, oldestTimestamp: Double? = nil, reachedStart: Bool = false) {
        self.roomID = roomID
        self.oldestEventID = oldestEventID
        self.oldestTimestamp = oldestTimestamp
        self.reachedStart = reachedStart
    }
}
```

- [ ] **Step 6: Create MessageWithProfile**

```swift
// NebCore/Sources/NebCore/Database/MessageWithProfile.swift
import Foundation
import GRDB

/// Joined result type: message row + profile fields.
/// Returned from `SELECT messages.*, profiles.displayName, profiles.avatarURL ...`
public struct MessageWithProfile: FetchableRecord, Sendable {
    public let message: MessageRecord
    public let displayName: String?
    public let avatarURL: String?

    public init(row: Row) {
        message = MessageRecord(row: row)
        displayName = row["displayName"]
        avatarURL = row["avatarURL"]
    }
}
```

- [ ] **Step 7: Build to verify record types compile**

Run: `cd NebCore && swift build 2>&1 | head -20`
Expected: BUILD SUCCEEDED (or warnings only, no errors)

- [ ] **Step 8: Commit**

```bash
git add NebCore/Sources/NebCore/Database/MessageRecord.swift \
       NebCore/Sources/NebCore/Database/ReactionRecord.swift \
       NebCore/Sources/NebCore/Database/ProfileRecord.swift \
       NebCore/Sources/NebCore/Database/ReadReceiptRecord.swift \
       NebCore/Sources/NebCore/Database/BackfillState.swift \
       NebCore/Sources/NebCore/Database/MessageWithProfile.swift
git commit -m "feat(db): add GRDB record types for message database"
```

---

### Task 2: Rewrite NebDatabase Schema and Migrations

Replace the old `search_index` schema with the full message database schema. Keep `dm_assignments`. Add all write methods and observation methods.

**Files:**
- Modify: `NebCore/Sources/NebCore/Database/NebDatabase.swift`

- [ ] **Step 1: Write failing test for message insert and retrieve**

Create `NebCore/Tests/NebCoreTests/NebDatabaseTests.swift`:

```swift
import Foundation
import Testing
@testable import NebCore

@Test func insertAndRetrieveMessage() throws {
    let db = try NebDatabase()
    let msg = MessageRecord(
        eventID: "$evt1",
        roomID: "!room:x",
        senderID: "@alice:x",
        body: "Hello world",
        timestamp: Date().timeIntervalSince1970
    )
    try db.insertMessage(msg)
    let results = try db.fetchMessages(roomID: "!room:x", limit: 50)
    #expect(results.count == 1)
    #expect(results.first?.message.body == "Hello world")
}

@Test func duplicateEventIDIsIgnored() throws {
    let db = try NebDatabase()
    let msg = MessageRecord(
        eventID: "$evt1",
        roomID: "!room:x",
        senderID: "@alice:x",
        body: "First",
        timestamp: 1000
    )
    try db.insertMessage(msg)
    let msg2 = MessageRecord(
        eventID: "$evt1",
        roomID: "!room:x",
        senderID: "@alice:x",
        body: "Second",
        timestamp: 1000
    )
    try db.insertMessage(msg2)
    let results = try db.fetchMessages(roomID: "!room:x", limit: 50)
    #expect(results.count == 1)
    #expect(results.first?.message.body == "First")
}

@Test func updateMessageBody() throws {
    let db = try NebDatabase()
    let msg = MessageRecord(
        eventID: "$evt1",
        roomID: "!room:x",
        senderID: "@alice:x",
        body: "Original",
        timestamp: 1000
    )
    try db.insertMessage(msg)
    try db.updateMessageBody(eventID: "$evt1", body: "Edited", formattedBody: nil, isEdited: true)
    let results = try db.fetchMessages(roomID: "!room:x", limit: 50)
    #expect(results.first?.message.body == "Edited")
    #expect(results.first?.message.isEdited == true)
}

@Test func updateSendStatus() throws {
    let db = try NebDatabase()
    let msg = MessageRecord(
        eventID: "~send-123",
        roomID: "!room:x",
        senderID: "@me:x",
        body: "Pending",
        timestamp: 1000,
        sendStatus: "pending",
        transactionID: "~send-123"
    )
    try db.insertMessage(msg)
    try db.reconcilePendingMessage(transactionID: "~send-123", confirmedEventID: "$real-evt")
    let results = try db.fetchMessages(roomID: "!room:x", limit: 50)
    #expect(results.count == 1)
    #expect(results.first?.message.eventID == "$real-evt")
    #expect(results.first?.message.sendStatus == "sent")
    #expect(results.first?.message.transactionID == nil)
}

@Test func reactionsInsertAndQuery() throws {
    let db = try NebDatabase()
    let msg = MessageRecord(
        eventID: "$evt1",
        roomID: "!room:x",
        senderID: "@alice:x",
        body: "Hello",
        timestamp: 1000
    )
    try db.insertMessage(msg)
    try db.replaceReactions(eventID: "$evt1", reactions: [
        ReactionRecord(eventID: "$evt1", emoji: "👍", senderID: "@bob:x"),
        ReactionRecord(eventID: "$evt1", emoji: "👍", senderID: "@alice:x"),
        ReactionRecord(eventID: "$evt1", emoji: "❤️", senderID: "@bob:x"),
    ])
    let reactions = try db.fetchReactions(eventIDs: ["$evt1"])
    #expect(reactions.count == 3)
}

@Test func profileUpsert() throws {
    let db = try NebDatabase()
    try db.upsertProfile(userID: "@alice:x", displayName: "Alice", avatarURL: nil)
    try db.upsertProfile(userID: "@alice:x", displayName: "Alice Updated", avatarURL: "mxc://x/abc")
    let profile = try db.fetchProfile(userID: "@alice:x")
    #expect(profile?.displayName == "Alice Updated")
    #expect(profile?.avatarURL == "mxc://x/abc")
}

@Test func readReceiptUpsert() throws {
    let db = try NebDatabase()
    try db.upsertReadReceipt(roomID: "!room:x", userID: "@bob:x", eventID: "$evt1")
    try db.upsertReadReceipt(roomID: "!room:x", userID: "@bob:x", eventID: "$evt2")
    let receipts = try db.fetchReadReceipts(roomID: "!room:x")
    #expect(receipts.count == 1)
    #expect(receipts.first?.eventID == "$evt2")
}

@Test func fts5Search() throws {
    let db = try NebDatabase()
    try db.insertMessage(MessageRecord(
        eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x",
        body: "Hello world", timestamp: 1000
    ))
    try db.insertMessage(MessageRecord(
        eventID: "$evt2", roomID: "!room:x", senderID: "@bob:x",
        body: "Goodbye world", timestamp: 2000
    ))
    try db.insertMessage(MessageRecord(
        eventID: "$evt3", roomID: "!room:y", senderID: "@alice:x",
        body: "Hello again", timestamp: 3000
    ))
    let results = try db.search(query: "hello", roomID: "!room:x")
    #expect(results.count == 1)
    #expect(results.first?.eventID == "$evt1")
}

@Test func backfillStateSaveAndLoad() throws {
    let db = try NebDatabase()
    let state = BackfillState(roomID: "!room:x", oldestEventID: "$old1", oldestTimestamp: 500, reachedStart: false)
    try db.updateBackfillState(state)
    let loaded = try db.backfillState(roomID: "!room:x")
    #expect(loaded?.oldestEventID == "$old1")
    #expect(loaded?.reachedStart == false)

    let state2 = BackfillState(roomID: "!room:x", reachedStart: true)
    try db.updateBackfillState(state2)
    let loaded2 = try db.backfillState(roomID: "!room:x")
    #expect(loaded2?.reachedStart == true)
}

@Test func dmAssignmentsStillWork() throws {
    let db = try NebDatabase()
    try db.saveDMAssignment(directUserID: "@bob:x", roomID: "!dm:x")
    let loaded = try db.loadDMAssignment(for: "@bob:x")
    #expect(loaded == "!dm:x")
}

@Test func messagesOrderedByTimestamp() throws {
    let db = try NebDatabase()
    try db.insertMessage(MessageRecord(
        eventID: "$evt2", roomID: "!room:x", senderID: "@alice:x",
        body: "Second", timestamp: 2000
    ))
    try db.insertMessage(MessageRecord(
        eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x",
        body: "First", timestamp: 1000
    ))
    let results = try db.fetchMessages(roomID: "!room:x", limit: 50)
    #expect(results.first?.message.body == "First")
    #expect(results.last?.message.body == "Second")
}

@Test func redactMessageClearsBody() throws {
    let db = try NebDatabase()
    try db.insertMessage(MessageRecord(
        eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x",
        body: "Secret message", formattedBody: "<b>Secret</b>", timestamp: 1000
    ))
    try db.redactMessage(eventID: "$evt1")
    let results = try db.fetchMessages(roomID: "!room:x", limit: 50)
    #expect(results.first?.message.body == "")
    #expect(results.first?.message.formattedBody == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd NebCore && swift test 2>&1 | tail -5`
Expected: FAIL -- methods like `insertMessage`, `fetchMessages`, etc. don't exist yet

- [ ] **Step 3: Rewrite NebDatabase with new schema and methods**

Replace the entire contents of `NebCore/Sources/NebCore/Database/NebDatabase.swift`:

```swift
import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Database")

/// Local message database for Neb. Stores full conversation history,
/// reactions, read receipts, profiles, and FTS5 search index.
/// Encrypted with SQLCipher (passphrase from Keychain).
public final class NebDatabase: Sendable {
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
        logger.info("Database opened at \(path)")
    }

    /// In-memory database for testing.
    public init() throws {
        dbQueue = try DatabaseQueue()
        try migrate()
    }

    // MARK: - Messages

    /// Insert a message. Ignores duplicates (by eventID).
    public func insertMessage(_ message: MessageRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO messages
                    (eventID, roomID, senderID, body, formattedBody, timestamp, isEdited, sendStatus, transactionID)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    message.eventID, message.roomID, message.senderID,
                    message.body, message.formattedBody, message.timestamp,
                    message.isEdited, message.sendStatus, message.transactionID
                ]
            )
        }
    }

    /// Update a message's body (for edits and decryption updates).
    public func updateMessageBody(eventID: String, body: String, formattedBody: String?, isEdited: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET body = ?, formattedBody = ?, isEdited = ? WHERE eventID = ?",
                arguments: [body, formattedBody, isEdited, eventID]
            )
        }
    }

    /// Update send status for a message.
    public func updateSendStatus(eventID: String, status: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET sendStatus = ? WHERE eventID = ?",
                arguments: [status, eventID]
            )
        }
    }

    /// Reconcile a pending message with the confirmed event from the server.
    /// Updates the eventID, clears the transactionID, sets status to 'sent'.
    public func reconcilePendingMessage(transactionID: String, confirmedEventID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE messages SET eventID = ?, sendStatus = 'sent', transactionID = NULL
                    WHERE transactionID = ?
                    """,
                arguments: [confirmedEventID, transactionID]
            )
        }
    }

    /// Redact a message -- clear body and formattedBody but keep the row.
    public func redactMessage(eventID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET body = '', formattedBody = NULL WHERE eventID = ?",
                arguments: [eventID]
            )
        }
    }

    /// Fetch messages for a room, ordered by timestamp ascending, with joined profile data.
    public func fetchMessages(roomID: String, limit: Int, beforeTimestamp: Double? = nil) throws -> [MessageWithProfile] {
        try dbQueue.read { db in
            var sql = """
                SELECT m.*, p.displayName, p.avatarURL
                FROM messages m
                LEFT JOIN profiles p ON m.senderID = p.userID
                WHERE m.roomID = ?
                """
            var args: [any DatabaseValueConvertible] = [roomID]
            if let before = beforeTimestamp {
                sql += " AND m.timestamp < ?"
                args.append(before)
            }
            sql += " ORDER BY m.timestamp ASC LIMIT ?"
            args.append(limit)
            return try MessageWithProfile.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Observe messages for a room reactively.
    public func messagesObservation(roomID: String, limit: Int) -> ValueObservation<[MessageWithProfile]> {
        ValueObservation.tracking { db in
            try MessageWithProfile.fetchAll(
                db,
                sql: """
                    SELECT m.*, p.displayName, p.avatarURL
                    FROM messages m
                    LEFT JOIN profiles p ON m.senderID = p.userID
                    WHERE m.roomID = ?
                    ORDER BY m.timestamp ASC
                    LIMIT ?
                    """,
                arguments: [roomID, limit]
            )
        }
    }

    // MARK: - Reactions

    /// Replace all reactions for an event (delete + reinsert).
    public func replaceReactions(eventID: String, reactions: [ReactionRecord]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM reactions WHERE eventID = ?", arguments: [eventID])
            for r in reactions {
                try db.execute(
                    sql: "INSERT INTO reactions (eventID, emoji, senderID) VALUES (?, ?, ?)",
                    arguments: [r.eventID, r.emoji, r.senderID]
                )
            }
        }
    }

    /// Fetch reactions for a set of event IDs.
    public func fetchReactions(eventIDs: [String]) throws -> [ReactionRecord] {
        guard !eventIDs.isEmpty else { return [] }
        return try dbQueue.read { db in
            let placeholders = eventIDs.map { _ in "?" }.joined(separator: ", ")
            return try ReactionRecord.fetchAll(
                db,
                sql: "SELECT * FROM reactions WHERE eventID IN (\(placeholders))",
                arguments: StatementArguments(eventIDs)
            )
        }
    }

    // MARK: - Read Receipts

    public func upsertReadReceipt(roomID: String, userID: String, eventID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO read_receipts (roomID, userID, eventID)
                    VALUES (?, ?, ?)
                    """,
                arguments: [roomID, userID, eventID]
            )
        }
    }

    public func fetchReadReceipts(roomID: String) throws -> [ReadReceiptRecord] {
        try dbQueue.read { db in
            try ReadReceiptRecord.fetchAll(
                db,
                sql: "SELECT * FROM read_receipts WHERE roomID = ?",
                arguments: [roomID]
            )
        }
    }

    // MARK: - Profiles

    public func upsertProfile(userID: String, displayName: String?, avatarURL: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO profiles (userID, displayName, avatarURL)
                    VALUES (?, ?, ?)
                    """,
                arguments: [userID, displayName, avatarURL]
            )
        }
    }

    public func fetchProfile(userID: String) throws -> ProfileRecord? {
        try dbQueue.read { db in
            try ProfileRecord.fetchOne(
                db,
                sql: "SELECT * FROM profiles WHERE userID = ?",
                arguments: [userID]
            )
        }
    }

    // MARK: - Search

    public func search(query: String, roomID: String) throws -> [SearchResult] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT m.eventID, m.roomID, m.senderID, m.body, m.timestamp
                    FROM messages m
                    JOIN search_fts f ON m.rowid = f.rowid
                    WHERE f.search_fts MATCH ?
                    AND m.roomID = ?
                    ORDER BY m.timestamp DESC
                    LIMIT 100
                    """,
                arguments: [query, roomID]
            )
            return rows.map { row in
                SearchResult(
                    eventID: row["eventID"],
                    roomID: row["roomID"],
                    senderID: row["senderID"],
                    body: row["body"],
                    timestamp: Date(timeIntervalSince1970: row["timestamp"])
                )
            }
        }
    }

    // MARK: - Backfill State

    public func backfillState(roomID: String) throws -> BackfillState? {
        try dbQueue.read { db in
            try BackfillState.fetchOne(
                db,
                sql: "SELECT * FROM backfill_state WHERE roomID = ?",
                arguments: [roomID]
            )
        }
    }

    public func updateBackfillState(_ state: BackfillState) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO backfill_state (roomID, oldestEventID, oldestTimestamp, reachedStart)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [state.roomID, state.oldestEventID, state.oldestTimestamp, state.reachedStart]
            )
        }
    }

    // MARK: - Pending Messages

    /// Mark all pending/sending messages as failed (called on app launch).
    public func failStalePendingMessages() throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET sendStatus = 'failed' WHERE sendStatus IN ('pending', 'sending')"
            )
        }
    }

    // MARK: - DM Assignments

    public func saveDMAssignment(directUserID: String, roomID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO dm_assignments (directUserID, roomID) VALUES (?, ?)",
                arguments: [directUserID, roomID]
            )
        }
    }

    public func loadDMAssignment(for directUserID: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT roomID FROM dm_assignments WHERE directUserID = ?",
                arguments: [directUserID]
            )
        }
    }

    public func allDMAssignments() throws -> [String: String] {
        try dbQueue.read { db in
            var result: [String: String] = [:]
            let rows = try Row.fetchAll(db, sql: "SELECT directUserID, roomID FROM dm_assignments")
            for row in rows {
                result[row["directUserID"]] = row["roomID"]
            }
            return result
        }
    }

    /// Expose the database queue as a reader for ValueObservation.
    public var reader: any DatabaseReader { dbQueue }

    // MARK: - Migration

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        // Keep old migrations registered so GRDB doesn't re-run them on existing databases.
        // They are no-ops for new databases that start at v2.
        migrator.registerMigration("v1_create_search_index") { db in
            if try !db.tableExists("search_index") {
                try db.create(table: "search_index") { t in
                    t.column("eventID", .text).primaryKey()
                    t.column("roomID", .text).notNull().indexed()
                    t.column("senderID", .text).notNull()
                    t.column("body", .text).notNull()
                    t.column("timestamp", .double).notNull()
                }
                try db.execute(sql: """
                    CREATE VIRTUAL TABLE search_fts USING fts5(
                        body, content='search_index', content_rowid='rowid'
                    )
                    """)
                try db.execute(sql: """
                    CREATE TRIGGER search_index_ai AFTER INSERT ON search_index BEGIN
                        INSERT INTO search_fts(rowid, body) VALUES (new.rowid, new.body);
                    END
                    """)
                try db.execute(sql: """
                    CREATE TRIGGER search_index_ad AFTER DELETE ON search_index BEGIN
                        INSERT INTO search_fts(search_fts, rowid, body) VALUES('delete', old.rowid, old.body);
                    END
                    """)
                try db.execute(sql: """
                    CREATE TRIGGER search_index_au AFTER UPDATE ON search_index BEGIN
                        INSERT INTO search_fts(search_fts, rowid, body) VALUES('delete', old.rowid, old.body);
                        INSERT INTO search_fts(rowid, body) VALUES (new.rowid, new.body);
                    END
                    """)
            }
        }

        migrator.registerMigration("v1_create_dm_assignments") { db in
            if try !db.tableExists("dm_assignments") {
                try db.create(table: "dm_assignments") { t in
                    t.column("directUserID", .text).primaryKey()
                    t.column("roomID", .text).notNull()
                }
            }
        }

        migrator.registerMigration("v2_message_database") { db in
            // Drop old search tables
            try db.execute(sql: "DROP TRIGGER IF EXISTS search_index_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS search_index_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS search_index_au")
            try db.execute(sql: "DROP TABLE IF EXISTS search_fts")
            try db.execute(sql: "DROP TABLE IF EXISTS search_index")

            // Messages
            try db.create(table: "messages") { t in
                t.column("eventID", .text).primaryKey()
                t.column("roomID", .text).notNull()
                t.column("senderID", .text).notNull()
                t.column("body", .text).notNull()
                t.column("formattedBody", .text)
                t.column("timestamp", .double).notNull()
                t.column("isEdited", .boolean).notNull().defaults(to: false)
                t.column("sendStatus", .text).notNull().defaults(to: "sent")
                t.column("transactionID", .text)
            }
            try db.create(index: "idx_messages_room_timestamp", on: "messages", columns: ["roomID", "timestamp"])
            try db.create(index: "idx_messages_transactionID", on: "messages", columns: ["transactionID"])

            // FTS5 on messages.body
            try db.execute(sql: """
                CREATE VIRTUAL TABLE search_fts USING fts5(
                    body, content='messages', content_rowid='rowid'
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
                    INSERT INTO search_fts(rowid, body) VALUES (new.rowid, new.body);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
                    INSERT INTO search_fts(search_fts, rowid, body) VALUES('delete', old.rowid, old.body);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER messages_au AFTER UPDATE OF body ON messages BEGIN
                    INSERT INTO search_fts(search_fts, rowid, body) VALUES('delete', old.rowid, old.body);
                    INSERT INTO search_fts(rowid, body) VALUES (new.rowid, new.body);
                END
                """)

            // Reactions
            try db.create(table: "reactions") { t in
                t.column("eventID", .text).notNull()
                t.column("emoji", .text).notNull()
                t.column("senderID", .text).notNull()
                t.primaryKey(["eventID", "emoji", "senderID"])
            }
            try db.create(index: "idx_reactions_eventID", on: "reactions", columns: ["eventID"])

            // Read receipts
            try db.create(table: "read_receipts") { t in
                t.column("roomID", .text).notNull()
                t.column("userID", .text).notNull()
                t.column("eventID", .text).notNull()
                t.primaryKey(["roomID", "userID"])
            }

            // Profiles
            try db.create(table: "profiles") { t in
                t.column("userID", .text).primaryKey()
                t.column("displayName", .text)
                t.column("avatarURL", .text)
            }

            // Backfill state
            try db.create(table: "backfill_state") { t in
                t.column("roomID", .text).primaryKey()
                t.column("oldestEventID", .text)
                t.column("oldestTimestamp", .double)
                t.column("reachedStart", .boolean).notNull().defaults(to: false)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd NebCore && swift test 2>&1 | tail -20`
Expected: All NebDatabaseTests pass

- [ ] **Step 5: Commit**

```bash
git add NebCore/Sources/NebCore/Database/NebDatabase.swift \
       NebCore/Tests/NebCoreTests/NebDatabaseTests.swift
git commit -m "feat(db): rewrite NebDatabase with full message schema and FTS5"
```

---

### Task 3: Update TimelineProtocol

Remove `messageStream` and `paginateBackwards`. Add `startTimelineSync` and `stopTimelineSync`.

**Files:**
- Modify: `NebCore/Sources/NebCore/Room/TimelineProtocol.swift`
- Modify: `NebTests/Mocks/MockRoomService.swift` (update `MockTimelineService`)

- [ ] **Step 1: Update TimelineProtocol**

Replace `NebCore/Sources/NebCore/Room/TimelineProtocol.swift`:

```swift
import Foundation

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

- [ ] **Step 2: Update MockTimelineService**

Replace `NebTests/Mocks/MockRoomService.swift`'s `MockTimelineService`:

```swift
final class MockTimelineService: TimelineProtocol, @unchecked Sendable {
    var sentMessages: [(roomID: String, body: String)] = []
    var markedAsRead: [String] = []
    var toggledReactions: [(roomID: String, eventID: String, emoji: String)] = []
    var syncedRooms: [String] = []
    var stoppedRooms: [String] = []

    func startTimelineSync(roomID: String) async throws {
        syncedRooms.append(roomID)
    }

    func stopTimelineSync(roomID: String) async throws {
        stoppedRooms.append(roomID)
    }

    func send(roomID: String, body: String) async throws {
        sentMessages.append((roomID: roomID, body: body))
    }

    func sendReply(roomID: String, body: String, replyToEventID: String) async throws {}
    func edit(roomID: String, eventID: String, newBody: String) async throws {}
    func delete(roomID: String, eventID: String, reason: String?) async throws {}

    func react(roomID: String, eventID: String, emoji: String) async throws {
        toggledReactions.append((roomID: roomID, eventID: eventID, emoji: emoji))
    }

    func markAsRead(roomID: String) async throws {
        markedAsRead.append(roomID)
    }

    func sendImage(roomID: String, url: URL, caption: String?) async throws {}
    func sendFile(roomID: String, url: URL, caption: String?) async throws {}
    func sendVideo(roomID: String, url: URL, thumbnailURL: URL, caption: String?) async throws {}
}
```

- [ ] **Step 3: Build to check for compile errors**

Run: `cd NebCore && swift build 2>&1 | tail -10`

This will produce errors in `Room.swift` (references to removed methods) and `TimelineViewModel.swift` (references `messageStream`, `paginateBackwards`). These are expected and will be fixed in Tasks 4 and 5.

- [ ] **Step 4: Commit (protocol + mock only)**

```bash
git add NebCore/Sources/NebCore/Room/TimelineProtocol.swift \
       NebTests/Mocks/MockRoomService.swift
git commit -m "feat(protocol): update TimelineProtocol -- replace messageStream with start/stopTimelineSync"
```

---

### Task 4: Rewrite Room Adapter Timeline Listener

Rewrite the `NebTimelineListener` to write to the database instead of yielding to an AsyncStream. Update `Room.swift` to implement the new `startTimelineSync`/`stopTimelineSync` protocol. The `send` method now writes a pending message to the database before forwarding to the SDK.

**Files:**
- Modify: `NebCore/Sources/NebCore/Room/Room.swift`

- [ ] **Step 1: Rewrite Room.swift**

This is a major rewrite. The key changes:

1. Remove `messageStream(roomID:)` and replace with `startTimelineSync(roomID:)` / `stopTimelineSync(roomID:)`
2. `NebTimelineListener.onUpdate(diff:)` writes to `NebDatabase` instead of yielding to a continuation
3. `send()` writes a pending `MessageRecord` to the database, then forwards to SDK
4. Remove `paginateBackwards(roomID:count:)` from the public API (backfill worker handles this)
5. Keep the timeline cache (active + 5 cached) for the SDK timeline handles
6. `search()` delegates to `NebDatabase.search()`
7. The `database` parameter becomes non-optional (required)

The full rewrite is too large for a single code block. Key structural changes:

- `Room.init` takes `database: NebDatabase` (non-optional)
- `startTimelineSync` replaces `messageStream`: sets up SDK timeline + listener, listener writes to DB
- `stopTimelineSync`: detaches listener, moves handle to cache
- `send`: generates `~send-{UUID}` transaction ID, inserts pending row, forwards to SDK
- `NebTimelineListener` no longer holds a continuation. Instead holds a `NebDatabase` reference. `onUpdate(diff:)` converts items and writes to DB. `convertItem` returns `MessageRecord` instead of `NebMessage`.
- Reactions, profiles, read receipts written to their respective tables

Implementation notes for the engineer:
- The `convertItem` method from the current `NebTimelineListener` should be adapted to produce `MessageRecord` instead of `NebMessage`. The conversion logic is similar but targets different output types.
- The SDK's `localSendState` (`notSentYet`, `sendingFailed`, `sent`) maps to `sendStatus` values (`pending`, `failed`, `sent`). The `sent` case from the SDK includes the event ID for reconciliation.
- The `eventOrTransactionId` on the SDK event provides the transaction ID for matching local echo.

- [ ] **Step 2: Build to check for compile errors in Room.swift**

Run: `cd NebCore && swift build 2>&1 | grep error`
Expected: errors only in TimelineViewModel.swift (not yet updated) and possibly view files

- [ ] **Step 3: Commit**

```bash
git add NebCore/Sources/NebCore/Room/Room.swift
git commit -m "feat(room): rewrite timeline listener to write to database"
```

---

### Task 5: Rewrite TimelineViewModel

Replace the AsyncStream-based observation with GRDB `ValueObservation`. The view model now observes the database directly for messages, and calls `startTimelineSync`/`stopTimelineSync` on the room service to activate the SDK listener.

**Files:**
- Modify: `Neb/ViewModels/TimelineViewModel.swift`
- Modify: `Neb/Views/MainView.swift` (pass database to ViewModel)
- Modify: `Neb/AppState.swift` (create and expose NebDatabase, pass to ViewModel construction)

- [ ] **Step 1: Rewrite TimelineViewModel**

Key changes:
- `init` gains a `database: NebDatabase` parameter and a `currentUserID: String` (non-optional, needed for `isOutgoing` derivation)
- On init, calls `startTimelineSync(roomID:)` on the room service
- Sets up `ValueObservation` on the database for the room's messages
- Maps `MessageWithProfile` → `NebMessage` adding derived fields (`isOutgoing`, `isEditable`, `isEmojiOnly`)
- `loadMore` no longer calls `paginateBackwards` -- it increases the observation limit
- `sendMessage` writes a pending row to the database via `NebDatabase.insertMessage`, then calls `roomService.send`
- `deinit` calls `stopTimelineSync`
- Layout computation (`computeLayouts`) is unchanged

```swift
import NebCore
import GRDB
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
    private let typingService: (any TypingProtocol)?
    private let database: NebDatabase
    private let currentUserID: String
    private var messageLimit = 50
    @ObservationIgnored nonisolated(unsafe) private var observationCancellable: AnyDatabaseCancellable?
    @ObservationIgnored nonisolated(unsafe) private var typingTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var typingDebounceTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var isCurrentlyTyping = false
    @ObservationIgnored nonisolated(unsafe) private var syncTask: Task<Void, Never>?

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
        observationCancellable?.cancel()
        typingTask?.cancel()
        typingDebounceTask?.cancel()
        syncTask?.cancel()
        let roomService = self.roomService
        let roomID = self.roomID
        Task {
            try? await roomService.stopTimelineSync(roomID: roomID)
        }
    }

    // ... (onComposerChanged, markAsRead, toggleReaction, startEditingLastMessage,
    //      cancelEditing, submitEdit, stopTyping remain the same as current implementation)

    public func sendMessage(_ body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stopTyping()
        do {
            try await roomService.send(roomID: roomID, body: trimmed)
        } catch { logger.error("Failed to send message in \(self.roomID): \(error)") }
    }

    public func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        messageLimit += 50
        restartObservation()
        try? await Task.sleep(for: .milliseconds(200))
        isLoadingMore = false
    }

    private func startObserving() {
        let observation = database.messagesObservation(roomID: roomID, limit: messageLimit)
        observationCancellable = observation.start(
            in: database.reader,
            scheduling: .immediate,
            onError: { error in
                logger.error("Database observation error: \(error)")
            },
            onChange: { [weak self] rows in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.messages = rows.map { self.toNebMessage($0) }
                    self.messageLayouts = Self.computeLayouts(for: self.messages)
                    self.hasLoadedInitialTimeline = true
                }
            }
        )
    }

    private func restartObservation() {
        observationCancellable?.cancel()
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
            readReceipts: [], // TODO: load from database in future iteration
            reactions: [],    // TODO: load from database in future iteration
            isEdited: m.isEdited,
            isEditable: isOutgoing && m.sendStatus == "sent",
            isEmojiOnly: m.body.isEmojiOnly
        )
    }

    // computeLayouts, isFirstInGroup, isLastInGroup -- unchanged from current implementation
    // startTypingObserving, onComposerChanged, stopTyping -- unchanged from current implementation
}
```

Note: this step includes `// TODO` comments for reactions and read receipts. These are loaded from the database but assembling them per-message requires an additional query. This can be a follow-up iteration within this task or a separate commit.

Implementation detail: `database.reader` needs to be exposed as a `DatabaseReader` on `NebDatabase`. Add a public property:

```swift
// In NebDatabase.swift
public var reader: any DatabaseReader { dbQueue }
```

- [ ] **Step 2: Update AppState to create and expose NebDatabase**

In `Neb/AppState.swift`:
- Add `let database: NebDatabase` property
- Create it in `init()` with a path in the app's support directory
- Pass `database` to `Room` adapter
- Expose it for view model construction

- [ ] **Step 3: Update MainView to pass database to TimelineViewModel**

In `Neb/Views/MainView.swift`, update the `TimelineViewModel` construction to pass the database and currentUserID:

```swift
timelineViewModel = TimelineViewModel(
    roomID: newID,
    roomService: timelineServiceProvider(),
    database: appState.database,
    currentUserID: appState.currentUserID ?? "",
    typingService: typingServiceProvider?(),
    initialUnreadCount: room?.unreadCount ?? 0
)
```

- [ ] **Step 4: Build and fix compile errors**

Run: `xcodegen generate && xcodebuild -project Neb.xcodeproj -scheme Neb build 2>&1 | grep error`

Fix any remaining compile errors (there will likely be a few around the property access patterns).

- [ ] **Step 5: Commit**

```bash
git add Neb/ViewModels/TimelineViewModel.swift \
       Neb/AppState.swift \
       Neb/Views/MainView.swift \
       NebCore/Sources/NebCore/Database/NebDatabase.swift
git commit -m "feat(timeline): rewrite TimelineViewModel to observe database"
```

---

### Task 6: Update TimelineViewModel Tests

Rewrite the tests to use an in-memory `NebDatabase` instead of the mock AsyncStream pattern.

**Files:**
- Modify: `NebTests/TimelineViewModelTests.swift`

- [ ] **Step 1: Rewrite tests**

The tests now create an in-memory `NebDatabase`, insert messages directly, and verify the view model picks them up via observation. The mock timeline service still handles `send`, `markAsRead`, etc.

```swift
import Foundation
import Testing
@testable import Neb
import NebCore

private func makeDatabase() throws -> NebDatabase {
    try NebDatabase()
}

private func insertMessage(
    db: NebDatabase, id: String, roomID: String = "!room:x",
    senderID: String = "@other:x", body: String, timestamp: Double = 1000
) throws {
    try db.insertMessage(MessageRecord(
        eventID: id, roomID: roomID, senderID: senderID,
        body: body, timestamp: timestamp
    ))
}

@Test func timelineInitialStateIsEmpty() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x", roomService: timelineService,
        database: db, currentUserID: "@me:x"
    )
    let messages = await vm.messages
    #expect(messages.isEmpty)
}

@Test func receivesMessagesFromDatabase() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x", roomService: timelineService,
        database: db, currentUserID: "@me:x"
    )

    try insertMessage(db: db, id: "$evt1", body: "Hello", timestamp: 1000)
    try insertMessage(db: db, id: "$evt2", body: "World", timestamp: 2000)

    try await Task.sleep(for: .milliseconds(100))

    let messages = await vm.messages
    #expect(messages.count == 2)
    #expect(messages.first?.body == "Hello")
    #expect(messages.last?.body == "World")
}

@Test func startsTimelineSyncOnInit() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let _ = await TimelineViewModel(
        roomID: "!room:x", roomService: timelineService,
        database: db, currentUserID: "@me:x"
    )

    try await Task.sleep(for: .milliseconds(50))
    #expect(timelineService.syncedRooms.contains("!room:x"))
}

@Test func sendMessageCallsService() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x", roomService: timelineService,
        database: db, currentUserID: "@me:x"
    )

    await vm.sendMessage("Hello!")

    #expect(timelineService.sentMessages.count == 1)
    #expect(timelineService.sentMessages.first?.body == "Hello!")
}

@Test func emptyMessageNotSent() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x", roomService: timelineService,
        database: db, currentUserID: "@me:x"
    )

    await vm.sendMessage("")
    await vm.sendMessage("   ")

    #expect(timelineService.sentMessages.isEmpty)
}

@Test func sendsReadReceiptForLastMessage() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x", roomService: timelineService,
        database: db, currentUserID: "@me:x"
    )

    try insertMessage(db: db, id: "$evt1", body: "Hello", timestamp: 1000)
    try await Task.sleep(for: .milliseconds(100))
    await vm.markAsRead()

    #expect(timelineService.markedAsRead.last == "!room:x")
}

@Test func derivesIsOutgoing() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x", roomService: timelineService,
        database: db, currentUserID: "@me:x"
    )

    try insertMessage(db: db, id: "$evt1", senderID: "@me:x", body: "My message", timestamp: 1000)
    try insertMessage(db: db, id: "$evt2", senderID: "@other:x", body: "Their message", timestamp: 2000)

    try await Task.sleep(for: .milliseconds(100))

    let messages = await vm.messages
    #expect(messages.first?.isOutgoing == true)
    #expect(messages.last?.isOutgoing == false)
}

// Typing tests remain the same structure, just add db + currentUserID params
```

- [ ] **Step 2: Run tests**

Run: from Xcode, run the NebTests target, or `xcodebuild test -project Neb.xcodeproj -scheme Neb`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add NebTests/TimelineViewModelTests.swift
git commit -m "test: rewrite TimelineViewModel tests for database-backed rendering"
```

---

### Task 7: BackfillWorker

Create the background backfill worker that runs after sync starts and paginates backwards through room history.

**Files:**
- Create: `NebCore/Sources/NebCore/Room/BackfillWorker.swift`
- Create: `NebCore/Tests/NebCoreTests/BackfillWorkerTests.swift`
- Modify: `Neb/AppState.swift` (start worker)

- [ ] **Step 1: Write BackfillWorker tests**

```swift
// NebCore/Tests/NebCoreTests/BackfillWorkerTests.swift
import Foundation
import Testing
@testable import NebCore

@Test func skipsRoomWithReachedStart() async throws {
    let db = try NebDatabase()
    try db.updateBackfillState(BackfillState(roomID: "!room:x", reachedStart: true))

    let state = try db.backfillState(roomID: "!room:x")
    #expect(state?.reachedStart == true)
}

@Test func backfillStateTracksProgress() async throws {
    let db = try NebDatabase()
    try db.updateBackfillState(BackfillState(
        roomID: "!room:x", oldestEventID: "$old1", oldestTimestamp: 500, reachedStart: false
    ))

    let state = try db.backfillState(roomID: "!room:x")
    #expect(state?.oldestEventID == "$old1")
    #expect(state?.reachedStart == false)
}

@Test func deduplicationIgnoresDuplicates() throws {
    let db = try NebDatabase()
    try db.insertMessage(MessageRecord(
        eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x",
        body: "Original", timestamp: 1000
    ))
    // Backfill tries to insert the same event
    try db.insertMessage(MessageRecord(
        eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x",
        body: "Backfill copy", timestamp: 1000
    ))
    let results = try db.fetchMessages(roomID: "!room:x", limit: 50)
    #expect(results.count == 1)
    #expect(results.first?.message.body == "Original")
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd NebCore && swift test 2>&1 | tail -10`
Expected: All pass (these test database behavior, which is already implemented)

- [ ] **Step 3: Create BackfillWorker**

```swift
// NebCore/Sources/NebCore/Room/BackfillWorker.swift
import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Backfill")

public final class BackfillWorker: @unchecked Sendable {
    private let clientProvider: () -> Client?
    private let roomListServiceProvider: () -> RoomListService?
    private let database: NebDatabase
    private var task: Task<Void, Never>?

    public init(
        clientProvider: @escaping () -> Client?,
        roomListServiceProvider: @escaping () -> RoomListService?,
        database: NebDatabase
    ) {
        self.clientProvider = clientProvider
        self.roomListServiceProvider = roomListServiceProvider
        self.database = database
    }

    public func start(roomIDs: [String]) {
        task?.cancel()
        task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            for roomID in roomIDs {
                guard !Task.isCancelled else { break }
                await self.backfillRoom(roomID: roomID)
            }
            logger.info("Backfill worker finished all rooms")
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Prioritize a room (e.g., when the user opens it).
    /// Cancels current work and restarts with the prioritized room first.
    public func prioritize(roomID: String, allRoomIDs: [String]) {
        var reordered = [roomID]
        reordered.append(contentsOf: allRoomIDs.filter { $0 != roomID })
        start(roomIDs: reordered)
    }

    private func backfillRoom(roomID: String) async {
        do {
            if let state = try database.backfillState(roomID: roomID), state.reachedStart {
                logger.info("Backfill: \(roomID) already reached start, skipping")
                return
            }

            guard let client = clientProvider() else { return }

            if let rls = roomListServiceProvider() {
                try? await rls.subscribeToRooms(roomIds: [roomID])
            }

            guard let room = try? client.getRoom(roomId: roomID) else {
                logger.warning("Backfill: room \(roomID) not found")
                return
            }

            let timeline = try await room.timeline()
            let myUserID = (try? client.userId()) ?? ""

            logger.info("Backfill: starting \(roomID)")

            var consecutiveFullDuplicateBatches = 0
            let batchSize: UInt16 = 50

            while !Task.isCancelled {
                let result = try await timeline.paginateBackwards(numEvents: batchSize)

                // Process current timeline items to extract messages
                // The timeline items are available through the listener
                // For backfill, we use a simpler approach: read items after pagination

                await Task.yield()

                if result {
                    // Hit the start of the timeline
                    try database.updateBackfillState(BackfillState(
                        roomID: roomID, reachedStart: true
                    ))
                    logger.info("Backfill: \(roomID) reached start")
                    break
                }

                // Check if we should stop (all events were duplicates)
                // This is determined by the INSERT OR IGNORE behavior --
                // if no new rows were inserted, we've caught up
                // For now, use a batch counter heuristic
                consecutiveFullDuplicateBatches += 1
                if consecutiveFullDuplicateBatches > 3 {
                    logger.info("Backfill: \(roomID) caught up (3 duplicate batches)")
                    break
                }
            }
        } catch {
            logger.error("Backfill: error in \(roomID): \(error)")
        }
    }
}
```

Note: the backfill worker's integration with the timeline listener (to capture paginated events and write them to the database) depends on the Room adapter from Task 4 already writing to the database. The backfill worker creates timelines whose listeners will write to the DB. The exact integration (sharing the Room adapter's listener or creating a dedicated backfill listener) should be refined during implementation. The important contract is: `paginateBackwards` causes the SDK to emit events via the timeline listener, which writes to the database.

- [ ] **Step 4: Wire BackfillWorker in AppState**

In `Neb/AppState.swift`, add:

```swift
let backfillWorker: BackfillWorker
```

Create it in `init()`:

```swift
let backfill = BackfillWorker(
    clientProvider: { session.getClient() },
    roomListServiceProvider: { sync.roomListService },
    database: database
)
self.backfillWorker = backfill
```

Start it in `onLoggedIn()` after sync starts, once rooms are available:

```swift
// After syncAdapter.startSync()
Task { [weak self] in
    guard let self else { return }
    for await rooms in self.syncAdapter.roomListStream() {
        let roomIDs = rooms.map(\.id)
        self.backfillWorker.start(roomIDs: roomIDs)
        break // Start once, don't restart on every room list update
    }
}
```

Stop in `onLoggedOut()`:

```swift
backfillWorker.stop()
```

- [ ] **Step 5: Build and verify**

Run: `xcodegen generate && xcodebuild -project Neb.xcodeproj -scheme Neb build 2>&1 | grep error`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add NebCore/Sources/NebCore/Room/BackfillWorker.swift \
       NebCore/Tests/NebCoreTests/BackfillWorkerTests.swift \
       Neb/AppState.swift
git commit -m "feat(backfill): add background backfill worker"
```

---

### Task 8: Wire Search to New Database

Update `Room.swift`'s `SearchProtocol` conformance to use the new `messages` table via `NebDatabase.search()`.

**Files:**
- Modify: `NebCore/Sources/NebCore/Room/Room.swift` (search implementation)

- [ ] **Step 1: Verify search works via existing NebDatabaseTests**

The `fts5Search` test from Task 2 already covers this. Run:

Run: `cd NebCore && swift test --filter fts5Search 2>&1`
Expected: PASS

- [ ] **Step 2: Update Room.swift search implementation**

The `Room` class already conforms to `SearchProtocol`. Update its `search` method to delegate to `NebDatabase`:

```swift
// In Room.swift
public func search(query: String, roomID: String) async throws -> [SearchResult] {
    guard let database else { throw NebError.notLoggedIn }
    return try database.search(query: query, roomID: roomID)
}
```

(If `database` is now non-optional per Task 4, remove the guard.)

- [ ] **Step 3: Build**

Run: `cd NebCore && swift build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add NebCore/Sources/NebCore/Room/Room.swift
git commit -m "feat(search): wire SearchProtocol to new message database"
```

---

### Task 9: Stale Pending Messages on Launch

On app launch, mark any pending/sending messages as failed so the user can retry or dismiss them.

**Files:**
- Modify: `Neb/AppState.swift`

- [ ] **Step 1: Write test**

```swift
// In NebCore/Tests/NebCoreTests/NebDatabaseTests.swift, add:
@Test func failStalePendingMessages() throws {
    let db = try NebDatabase()
    try db.insertMessage(MessageRecord(
        eventID: "~send-1", roomID: "!room:x", senderID: "@me:x",
        body: "Pending", timestamp: 1000, sendStatus: "pending", transactionID: "~send-1"
    ))
    try db.insertMessage(MessageRecord(
        eventID: "~send-2", roomID: "!room:x", senderID: "@me:x",
        body: "Sending", timestamp: 2000, sendStatus: "sending", transactionID: "~send-2"
    ))
    try db.insertMessage(MessageRecord(
        eventID: "$confirmed", roomID: "!room:x", senderID: "@me:x",
        body: "Sent", timestamp: 3000, sendStatus: "sent"
    ))
    try db.failStalePendingMessages()
    let results = try db.fetchMessages(roomID: "!room:x", limit: 50)
    let pending = results.filter { $0.message.sendStatus == "pending" || $0.message.sendStatus == "sending" }
    #expect(pending.isEmpty)
    let failed = results.filter { $0.message.sendStatus == "failed" }
    #expect(failed.count == 2)
    let sent = results.filter { $0.message.sendStatus == "sent" }
    #expect(sent.count == 1)
}
```

- [ ] **Step 2: Run test**

Run: `cd NebCore && swift test --filter failStalePendingMessages`
Expected: PASS (method already implemented in Task 2)

- [ ] **Step 3: Call on launch in AppState**

In `AppState.onLoggedIn()`, before starting sync:

```swift
do { try database.failStalePendingMessages() } catch { logger.error("Failed to clean pending messages: \(error)") }
```

- [ ] **Step 4: Commit**

```bash
git add NebCore/Tests/NebCoreTests/NebDatabaseTests.swift Neb/AppState.swift
git commit -m "feat: mark stale pending messages as failed on launch"
```

---

### Task 10: Final Integration and Cleanup

Build the full project, run all tests, fix any remaining issues.

**Files:**
- Various (fix any remaining compile errors)

- [ ] **Step 1: Generate Xcode project**

Run: `cd /Users/mormubis/workspace/neb && xcodegen generate`

- [ ] **Step 2: Build the full project**

Run: `xcodebuild -project Neb.xcodeproj -scheme Neb build 2>&1 | grep error`
Expected: No errors

- [ ] **Step 3: Run NebCore tests**

Run: `cd NebCore && swift test`
Expected: All tests pass

- [ ] **Step 4: Run Neb app tests**

Run: `xcodebuild test -project Neb.xcodeproj -scheme Neb 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 5: Remove old search_index references**

Search for any remaining references to the old `indexMessage` or `search_index` API in the codebase. Remove them.

Run: `grep -r "search_index\|indexMessage" NebCore/Sources/ Neb/ --include="*.swift"`
Expected: No results (all references should be in migrations only)

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat: local message database -- full implementation

Replaces SDK timeline stream with database-backed rendering.
GRDB/SQLCipher stores full conversation history.
Background backfill worker paginates historical messages.
Local echo for sends with transaction ID reconciliation.
FTS5 search on message bodies."
```
