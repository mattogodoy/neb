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
        eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x",
        body: "First", timestamp: 1000
    )
    try db.insertMessage(msg)
    let msg2 = MessageRecord(
        eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x",
        body: "Second", timestamp: 1000
    )
    try db.insertMessage(msg2)
    let results = try db.fetchMessages(roomID: "!room:x", limit: 50)
    #expect(results.count == 1)
    #expect(results.first?.message.body == "First")
}

@Test func updateMessageBody() throws {
    let db = try NebDatabase()
    let msg = MessageRecord(
        eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x",
        body: "Original", timestamp: 1000
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
        eventID: "~send-123", roomID: "!room:x", senderID: "@me:x",
        body: "Pending", timestamp: 1000, sendStatus: "pending", transactionID: "~send-123"
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
        eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x",
        body: "Hello", timestamp: 1000
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

// MARK: - Room tests

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
    try db.upsertRoom(RoomRecord(roomID: "!room:x", name: "Old Name", unreadCount: 0, isDirect: false, memberCount: 2))
    try db.upsertRoom(RoomRecord(roomID: "!room:x", name: "New Name", unreadCount: 5, isDirect: false, memberCount: 3))
    let rooms = try db.fetchRooms()
    #expect(rooms.count == 1)
    #expect(rooms.first?.name == "New Name")
    #expect(rooms.first?.unreadCount == 5)
}

@Test func deleteRoom() throws {
    let db = try NebDatabase()
    try db.upsertRoom(RoomRecord(roomID: "!room:x", name: "Room", unreadCount: 0, isDirect: false, memberCount: 1))
    try db.deleteRoom(roomID: "!room:x")
    let rooms = try db.fetchRooms()
    #expect(rooms.isEmpty)
}

@Test func roomListIncludesLastMessage() throws {
    let db = try NebDatabase()
    try db.upsertRoom(RoomRecord(roomID: "!room:x", name: "Room", unreadCount: 0, isDirect: false, memberCount: 2))
    try db.insertMessage(MessageRecord(eventID: "$evt1", roomID: "!room:x", senderID: "@alice:x", body: "Hello", timestamp: 1000))
    try db.insertMessage(MessageRecord(eventID: "$evt2", roomID: "!room:x", senderID: "@bob:x", body: "World", timestamp: 2000))
    let rooms = try db.fetchRoomList()
    #expect(rooms.count == 1)
    #expect(rooms.first?.lastMessage == "World")
    #expect(rooms.first?.lastMessageTimestamp == Date(timeIntervalSince1970: 2000))
}

@Test func roomListSortedByLatestMessage() throws {
    let db = try NebDatabase()
    try db.upsertRoom(RoomRecord(roomID: "!old:x", name: "Old Room", unreadCount: 0, isDirect: false, memberCount: 1))
    try db.upsertRoom(RoomRecord(roomID: "!new:x", name: "New Room", unreadCount: 0, isDirect: false, memberCount: 1))
    try db.insertMessage(MessageRecord(eventID: "$evt1", roomID: "!old:x", senderID: "@alice:x", body: "Old msg", timestamp: 1000))
    try db.insertMessage(MessageRecord(eventID: "$evt2", roomID: "!new:x", senderID: "@alice:x", body: "New msg", timestamp: 2000))
    let rooms = try db.fetchRoomList()
    #expect(rooms.first?.id == "!new:x")
    #expect(rooms.last?.id == "!old:x")
}

@Test func roomWithNoMessagesAppearsLast() throws {
    let db = try NebDatabase()
    try db.upsertRoom(RoomRecord(roomID: "!empty:x", name: "Empty", unreadCount: 0, isDirect: false, memberCount: 1))
    try db.upsertRoom(RoomRecord(roomID: "!active:x", name: "Active", unreadCount: 0, isDirect: false, memberCount: 1))
    try db.insertMessage(MessageRecord(eventID: "$evt1", roomID: "!active:x", senderID: "@alice:x", body: "Hello", timestamp: 1000))
    let rooms = try db.fetchRoomList()
    #expect(rooms.first?.id == "!active:x")
    #expect(rooms.last?.id == "!empty:x")
}

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

@Test func fetchPendingMessages() throws {
    let db = try NebDatabase()

    let pending = MessageRecord(
        eventID: "~send-1",
        roomID: "!room:example.com",
        senderID: "@me:example.com",
        body: "hello",
        timestamp: 1000,
        sendStatus: "pending",
        transactionID: "~send-1"
    )
    let sent = MessageRecord(
        eventID: "$sent1",
        roomID: "!room:example.com",
        senderID: "@me:example.com",
        body: "already sent",
        timestamp: 999,
        sendStatus: "sent"
    )
    try db.insertMessage(sent)
    try db.insertMessage(pending)

    let results = try db.fetchPendingMessages()
    #expect(results.count == 1)
    #expect(results[0].eventID == "~send-1")
    #expect(results[0].body == "hello")
}
