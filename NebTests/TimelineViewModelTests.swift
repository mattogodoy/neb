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
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x"
    )
    let messages = await vm.messages
    #expect(messages.isEmpty)
}

@Test func receivesMessagesFromDatabase() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x"
    )

    try insertMessage(db: db, id: "1", body: "Hello", timestamp: 1000)
    try insertMessage(db: db, id: "2", body: "World", timestamp: 2000)

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
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x"
    )

    try await Task.sleep(for: .milliseconds(100))

    #expect(timelineService.syncedRooms.contains("!room:x"))
}

@Test func sendMessageCallsService() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x"
    )

    await vm.sendMessage("Hello!")

    #expect(timelineService.sentMessages.count == 1)
    #expect(timelineService.sentMessages.first?.body == "Hello!")
}

@Test func emptyMessageNotSent() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x"
    )

    await vm.sendMessage("")
    await vm.sendMessage("   ")

    #expect(timelineService.sentMessages.isEmpty)
}

@Test func sendsReadReceiptForLastMessage() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x"
    )

    try insertMessage(db: db, id: "evt-1", body: "Hello", timestamp: 1000)
    try insertMessage(db: db, id: "evt-2", body: "World", timestamp: 2000)

    try await Task.sleep(for: .milliseconds(100))

    await vm.markAsRead()

    #expect(timelineService.markedAsRead.last == "!room:x")
}

@Test func derivesIsOutgoing() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x"
    )

    try insertMessage(db: db, id: "1", senderID: "@me:x", body: "Mine", timestamp: 1000)
    try insertMessage(db: db, id: "2", senderID: "@other:x", body: "Theirs", timestamp: 2000)

    try await Task.sleep(for: .milliseconds(100))

    let messages = await vm.messages
    #expect(messages.count == 2)
    #expect(messages.first?.isOutgoing == true)
    #expect(messages.last?.isOutgoing == false)
}

@Test func receivesTypingUsers() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let typingService = MockTypingService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x",
        typingService: typingService
    )

    try await Task.sleep(for: .milliseconds(10))

    let alice = NebUser(id: "@alice:x", displayName: "Alice")
    typingService.emitTypingUsers(roomID: "!room:x", users: [alice])

    try await Task.sleep(for: .milliseconds(50))

    let typing = await vm.typingUsers
    #expect(typing.count == 1)
    #expect(typing.first?.id == "@alice:x")
}

@Test func filtersOutCurrentUser() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let typingService = MockTypingService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x",
        typingService: typingService
    )

    try await Task.sleep(for: .milliseconds(10))

    let me = NebUser(id: "@me:x", displayName: "Me")
    let alice = NebUser(id: "@alice:x", displayName: "Alice")
    typingService.emitTypingUsers(roomID: "!room:x", users: [me, alice])

    try await Task.sleep(for: .milliseconds(50))

    let typing = await vm.typingUsers
    #expect(typing.count == 1)
    #expect(typing.first?.id == "@alice:x")
}

@Test func sendsTypingNoticeOnComposerChange() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let typingService = MockTypingService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x",
        typingService: typingService
    )

    await vm.onComposerChanged(text: "Hello")

    try await Task.sleep(for: .milliseconds(50))

    #expect(typingService.typingNotices.contains { $0.roomID == "!room:x" && $0.isTyping == true })
}

@Test func sendsStopTypingOnSend() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let typingService = MockTypingService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x",
        typingService: typingService
    )

    await vm.onComposerChanged(text: "Hello")
    try await Task.sleep(for: .milliseconds(50))

    await vm.sendMessage("Hello")

    try await Task.sleep(for: .milliseconds(50))

    let lastNotice = typingService.typingNotices.last
    #expect(lastNotice?.roomID == "!room:x")
    #expect(lastNotice?.isTyping == false)
}

@Test func doesNotSendTypingForEmptyText() async throws {
    let db = try makeDatabase()
    let timelineService = MockTimelineService()
    let typingService = MockTypingService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: timelineService,
        database: db,
        currentUserID: "@me:x",
        typingService: typingService
    )

    await vm.onComposerChanged(text: "")

    try await Task.sleep(for: .milliseconds(50))

    #expect(typingService.typingNotices.isEmpty)
}
