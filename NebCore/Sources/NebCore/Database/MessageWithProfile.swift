import Foundation
import GRDB

/// Joined result type: message row + profile fields.
/// Returned from `SELECT messages.*, profiles.displayName, profiles.avatarURL ...`
public struct MessageWithProfile: FetchableRecord, Sendable {
    public let message: MessageRecord
    public let displayName: String?
    public let avatarURL: String?

    public init(row: Row) throws {
        message = try MessageRecord(row: row)
        displayName = row["displayName"]
        avatarURL = row["avatarURL"]
    }
}
