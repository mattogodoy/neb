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
