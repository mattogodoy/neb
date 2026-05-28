import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Database")

/// Internal database for Neb's local data (messages, reactions, profiles, DM assignments, etc.).
/// Not exposed to the app layer — used by adapters internally.
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

    /// Exposes the underlying reader for ValueObservation use.
    public var reader: any DatabaseReader { dbQueue }

    // MARK: - Messages

    /// Insert a message. Silently ignores duplicate eventIDs (INSERT OR IGNORE).
    public func insertMessage(_ message: MessageRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO messages
                        (eventID, roomID, senderID, body, formattedBody, timestamp,
                         isEdited, sendStatus, transactionID)
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

    /// Update the body of an existing message (e.g. after an edit event).
    public func updateMessageBody(eventID: String, body: String, formattedBody: String?, isEdited: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE messages
                    SET body = ?, formattedBody = ?, isEdited = ?
                    WHERE eventID = ?
                    """,
                arguments: [body, formattedBody, isEdited, eventID]
            )
        }
    }

    /// Update the send status of a message.
    public func updateSendStatus(eventID: String, status: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET sendStatus = ? WHERE eventID = ?",
                arguments: [status, eventID]
            )
        }
    }

    /// When the server confirms a pending message, replace the local transaction ID
    /// with the real event ID and mark it as sent.
    public func reconcilePendingMessage(transactionID: String, confirmedEventID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE messages
                    SET eventID = ?, sendStatus = 'sent', transactionID = NULL
                    WHERE transactionID = ?
                    """,
                arguments: [confirmedEventID, transactionID]
            )
        }
    }

    /// Delete a message by eventID.
    public func deleteMessage(eventID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM messages WHERE eventID = ?",
                arguments: [eventID]
            )
        }
    }

    /// Clear body and formattedBody for a redacted message.
    public func redactMessage(eventID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET body = '', formattedBody = NULL WHERE eventID = ?",
                arguments: [eventID]
            )
        }
    }

    /// Mark all pending/sending messages as failed (e.g. on app relaunch).
    public func failStalePendingMessages() throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE messages
                    SET sendStatus = 'failed'
                    WHERE sendStatus IN ('pending', 'sending')
                    """
            )
        }
    }

    /// Fetch all messages with pending/sending status, ordered by timestamp.
    public func fetchPendingMessages() throws -> [MessageRecord] {
        try dbQueue.read { db in
            try MessageRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM messages
                    WHERE sendStatus IN ('pending', 'sending')
                    ORDER BY timestamp ASC
                    """
            )
        }
    }

    /// Fetch messages for a room ordered by timestamp ASC.
    public func fetchMessages(roomID: String, limit: Int) throws -> [MessageWithProfile] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT messages.*, profiles.displayName, profiles.avatarURL
                    FROM messages
                    LEFT JOIN profiles ON messages.senderID = profiles.userID
                    WHERE messages.roomID = ?
                    ORDER BY messages.timestamp ASC
                    LIMIT ?
                    """,
                arguments: [roomID, limit]
            )
            return try rows.map { try MessageWithProfile(row: $0) }
        }
    }

    // MARK: - Reactions

    /// Replace all reactions for a given event with a new set.
    public func replaceReactions(eventID: String, reactions: [ReactionRecord]) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM reactions WHERE eventID = ?",
                arguments: [eventID]
            )
            for reaction in reactions {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO reactions (eventID, emoji, senderID)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [reaction.eventID, reaction.emoji, reaction.senderID]
                )
            }
        }
    }

    /// Fetch reactions for a set of event IDs.
    public func fetchReactions(eventIDs: [String]) throws -> [ReactionRecord] {
        guard !eventIDs.isEmpty else { return [] }
        return try dbQueue.read { db in
            let placeholders = eventIDs.map { _ in "?" }.joined(separator: ", ")
            let args = StatementArguments(eventIDs)
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT eventID, emoji, senderID FROM reactions WHERE eventID IN (\(placeholders))",
                arguments: args
            )
            return rows.map { ReactionRecord(eventID: $0["eventID"], emoji: $0["emoji"], senderID: $0["senderID"]) }
        }
    }

    // MARK: - Profiles

    /// Insert or replace a user profile.
    public func upsertProfile(userID: String, displayName: String?, avatarURL: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO profiles (userID, displayName, avatarURL)
                    VALUES (?, ?, ?)
                    ON CONFLICT(userID) DO UPDATE SET
                        displayName = excluded.displayName,
                        avatarURL = excluded.avatarURL
                    """,
                arguments: [userID, displayName, avatarURL]
            )
        }
    }

    /// Fetch a single user profile.
    public func fetchProfile(userID: String) throws -> ProfileRecord? {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT userID, displayName, avatarURL FROM profiles WHERE userID = ?",
                arguments: [userID]
            )
            return rows.first.map { ProfileRecord(userID: $0["userID"], displayName: $0["displayName"], avatarURL: $0["avatarURL"]) }
        }
    }

    // MARK: - Read Receipts

    /// Upsert a read receipt (one per room+user, tracks most recent event).
    public func upsertReadReceipt(roomID: String, userID: String, eventID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO read_receipts (roomID, userID, eventID)
                    VALUES (?, ?, ?)
                    ON CONFLICT(roomID, userID) DO UPDATE SET eventID = excluded.eventID
                    """,
                arguments: [roomID, userID, eventID]
            )
        }
    }

    /// Fetch all read receipts for a room.
    public func fetchReadReceipts(roomID: String) throws -> [ReadReceiptRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT roomID, userID, eventID FROM read_receipts WHERE roomID = ?",
                arguments: [roomID]
            )
            return rows.map { ReadReceiptRecord(roomID: $0["roomID"], userID: $0["userID"], eventID: $0["eventID"]) }
        }
    }

    // MARK: - Backfill State

    /// Save or replace the backfill state for a room.
    public func updateBackfillState(_ state: BackfillState) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO backfill_state (roomID, oldestEventID, oldestTimestamp, reachedStart)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(roomID) DO UPDATE SET
                        oldestEventID = excluded.oldestEventID,
                        oldestTimestamp = excluded.oldestTimestamp,
                        reachedStart = excluded.reachedStart
                    """,
                arguments: [state.roomID, state.oldestEventID, state.oldestTimestamp, state.reachedStart]
            )
        }
    }

    /// Fetch the backfill state for a room.
    public func backfillState(roomID: String) throws -> BackfillState? {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT roomID, oldestEventID, oldestTimestamp, reachedStart FROM backfill_state WHERE roomID = ?",
                arguments: [roomID]
            )
            return rows.first.map {
                BackfillState(
                    roomID: $0["roomID"],
                    oldestEventID: $0["oldestEventID"],
                    oldestTimestamp: $0["oldestTimestamp"],
                    reachedStart: $0["reachedStart"]
                )
            }
        }
    }

    // MARK: - Search

    /// Full-text search over message bodies, scoped to a room.
    public func search(query: String, roomID: String) throws -> [SearchResult] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT m.eventID, m.roomID, m.senderID, m.body, m.timestamp
                    FROM messages m
                    JOIN messages_fts f ON m.rowid = f.rowid
                    WHERE messages_fts MATCH ?
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

    // MARK: - Observation

    /// Returns a ValueObservation that emits messages for a room whenever they change.
    public func messagesObservation(roomID: String, limit: Int = 50) -> ValueObservation<ValueReducers.Fetch<[MessageWithProfile]>> {
        ValueObservation.tracking { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT messages.*, profiles.displayName, profiles.avatarURL
                    FROM messages
                    LEFT JOIN profiles ON messages.senderID = profiles.userID
                    WHERE messages.roomID = ?
                    ORDER BY messages.timestamp ASC
                    LIMIT ?
                    """,
                arguments: [roomID, limit]
            )
            return try rows.map { try MessageWithProfile(row: $0) }
        }
    }

    /// Observe messages for a room as an AsyncStream. Emits immediately with current rows,
    /// then re-emits whenever the database changes. The stream ends when the caller cancels.
    @MainActor
    public func observeMessages(roomID: String, limit: Int = 50) -> AsyncStream<[MessageWithProfile]> {
        AsyncStream { continuation in
            let observation = messagesObservation(roomID: roomID, limit: limit)
            let cancellable = observation.start(
                in: dbQueue,
                scheduling: .immediate,
                onError: { error in
                    logger.error("observeMessages error for \(roomID): \(error)")
                    continuation.finish()
                },
                onChange: { rows in
                    continuation.yield(rows)
                }
            )
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    // MARK: - Rooms

    /// Insert or replace a room record.
    public func upsertRoom(_ room: RoomRecord) throws {
        try dbQueue.write { db in
            try room.upsert(db)
        }
    }

    /// Delete a room by ID.
    public func deleteRoom(roomID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM rooms WHERE roomID = ?",
                arguments: [roomID]
            )
        }
    }

    /// Fetch all room records.
    public func fetchRooms() throws -> [RoomRecord] {
        try dbQueue.read { db in
            try RoomRecord.fetchAll(db)
        }
    }

    /// Fetch rooms joined with their latest message, sorted by most recent activity.
    public func fetchRoomList() throws -> [NebRoom] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
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
                    """
            )
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

    /// Observe the room list as an AsyncStream. Emits immediately with current rows,
    /// then re-emits whenever the database changes. The stream ends when the caller cancels.
    @MainActor
    public func roomListObservation() -> AsyncStream<[NebRoom]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db -> [NebRoom] in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
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
                        """
                )
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
                in: dbQueue,
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

    // MARK: - DM Assignments

    public func saveDMAssignment(directUserID: String, roomID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO dm_assignments (directUserID, roomID)
                    VALUES (?, ?)
                    """,
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

    // MARK: - Migration

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        // v1 migrations kept so GRDB doesn't re-run them on existing databases.
        // Guarded with tableExists checks for fresh (in-memory) databases.
        migrator.registerMigration("v1_create_search_index") { db in
            guard try !db.tableExists("search_index") else { return }
            try db.create(table: "search_index") { t in
                t.column("eventID", .text).primaryKey()
                t.column("roomID", .text).notNull().indexed()
                t.column("senderID", .text).notNull()
                t.column("body", .text).notNull()
                t.column("timestamp", .double).notNull()
            }
            try db.execute(sql: """
                CREATE VIRTUAL TABLE search_fts USING fts5(
                    body,
                    content='search_index',
                    content_rowid='rowid'
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

        migrator.registerMigration("v1_create_dm_assignments") { db in
            guard try !db.tableExists("dm_assignments") else { return }
            try db.create(table: "dm_assignments") { t in
                t.column("directUserID", .text).primaryKey()
                t.column("roomID", .text).notNull()
            }
        }

        migrator.registerMigration("v2_message_database") { db in
            // Drop old search infrastructure
            if try db.tableExists("search_index") {
                try db.execute(sql: "DROP TRIGGER IF EXISTS search_index_ai")
                try db.execute(sql: "DROP TRIGGER IF EXISTS search_index_ad")
                try db.execute(sql: "DROP TRIGGER IF EXISTS search_index_au")
                try db.execute(sql: "DROP TABLE IF EXISTS search_fts")
                try db.execute(sql: "DROP TABLE IF EXISTS search_index")
            }

            // messages
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
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_messages_room_ts ON messages (roomID, timestamp)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_messages_transaction ON messages (transactionID) WHERE transactionID IS NOT NULL")

            // reactions — composite PK (eventID, emoji, senderID)
            try db.create(table: "reactions") { t in
                t.column("eventID", .text).notNull()
                t.column("emoji", .text).notNull()
                t.column("senderID", .text).notNull()
                t.primaryKey(["eventID", "emoji", "senderID"])
            }

            // read_receipts — one per (roomID, userID)
            try db.create(table: "read_receipts") { t in
                t.column("roomID", .text).notNull()
                t.column("userID", .text).notNull()
                t.column("eventID", .text).notNull()
                t.primaryKey(["roomID", "userID"])
            }

            // profiles
            try db.create(table: "profiles") { t in
                t.column("userID", .text).primaryKey()
                t.column("displayName", .text)
                t.column("avatarURL", .text)
            }

            // backfill_state — one row per room
            try db.create(table: "backfill_state") { t in
                t.column("roomID", .text).primaryKey()
                t.column("oldestEventID", .text)
                t.column("oldestTimestamp", .double)
                t.column("reachedStart", .boolean).notNull().defaults(to: false)
            }

            // FTS5 external content table over messages.body
            try db.execute(sql: """
                CREATE VIRTUAL TABLE messages_fts USING fts5(
                    body,
                    content='messages',
                    content_rowid='rowid'
                )
                """)

            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
                    INSERT INTO messages_fts(rowid, body) VALUES (new.rowid, new.body);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
                    INSERT INTO messages_fts(messages_fts, rowid, body) VALUES('delete', old.rowid, old.body);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER messages_au AFTER UPDATE OF body ON messages BEGIN
                    INSERT INTO messages_fts(messages_fts, rowid, body) VALUES('delete', old.rowid, old.body);
                    INSERT INTO messages_fts(rowid, body) VALUES (new.rowid, new.body);
                END
                """)
        }

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

        try migrator.migrate(dbQueue)
    }
}

// MARK: - Search Result

public struct SearchResult: Sendable, Equatable {
    public let eventID: String
    public let roomID: String
    public let senderID: String
    public let body: String
    public let timestamp: Date
}
