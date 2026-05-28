import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Database")

/// Internal database for Neb's local data (search index, DM assignments).
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

    // MARK: - Search Index

    public func indexMessage(eventID: String, roomID: String, senderID: String, body: String, timestamp: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO search_index (eventID, roomID, senderID, body, timestamp)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [eventID, roomID, senderID, body, timestamp.timeIntervalSince1970]
            )
        }
    }

    public func search(query: String, roomID: String) throws -> [SearchResult] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT s.eventID, s.roomID, s.senderID, s.body, s.timestamp
                    FROM search_index s
                    JOIN search_fts f ON s.rowid = f.rowid
                    WHERE f.search_fts MATCH ?
                    AND s.roomID = ?
                    ORDER BY s.timestamp DESC
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

        migrator.registerMigration("v1_create_search_index") { db in
            // Content table
            try db.create(table: "search_index") { t in
                t.column("eventID", .text).primaryKey()
                t.column("roomID", .text).notNull().indexed()
                t.column("senderID", .text).notNull()
                t.column("body", .text).notNull()
                t.column("timestamp", .double).notNull()
            }

            // FTS5 external content table
            try db.execute(sql: """
                CREATE VIRTUAL TABLE search_fts USING fts5(
                    body,
                    content='search_index',
                    content_rowid='rowid'
                )
                """)

            // Triggers to keep FTS in sync
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
            try db.create(table: "dm_assignments") { t in
                t.column("directUserID", .text).primaryKey()
                t.column("roomID", .text).notNull()
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
