import Foundation
import Testing
@testable import NebCore

private func makeMessage(id: String, body: String, isOutgoing: Bool = false) -> NebMessage {
    NebMessage(
        id: id,
        roomID: "!room:x",
        senderID: isOutgoing ? "@me:x" : "@other:x",
        senderDisplayName: isOutgoing ? "Me" : "Other",
        body: body,
        timestamp: Date(),
        isOutgoing: isOutgoing
    )
}

@Test func timelineInitialStateIsEmpty() async {
    let roomService = MockRoomService()
    let vm = await TimelineViewModel(roomID: "!room:x", roomService: roomService)
    let messages = await vm.messages
    #expect(messages.isEmpty)
}

@Test func receivesMessages() async throws {
    let roomService = MockRoomService()
    let vm = await TimelineViewModel(roomID: "!room:x", roomService: roomService)

    roomService.emitMessages(roomID: "!room:x", messages: [
        makeMessage(id: "1", body: "Hello"),
        makeMessage(id: "2", body: "World"),
    ])

    try await Task.sleep(for: .milliseconds(50))

    let messages = await vm.messages
    #expect(messages.count == 2)
    #expect(messages.first?.body == "Hello")
}

@Test func sendsReadReceiptForLastMessage() async throws {
    let roomService = MockRoomService()
    let vm = await TimelineViewModel(roomID: "!room:x", roomService: roomService)

    roomService.emitMessages(roomID: "!room:x", messages: [
        makeMessage(id: "evt-1", body: "Hello"),
        makeMessage(id: "evt-2", body: "World"),
    ])

    try await Task.sleep(for: .milliseconds(50))
    await vm.markAsRead()

    #expect(roomService.readReceipts.last?.eventID == "evt-2")
}

@Test func sendMessageAppendsLocally() async throws {
    let roomService = MockRoomService()
    let vm = await TimelineViewModel(roomID: "!room:x", roomService: roomService)

    await vm.sendMessage("Hello!")

    #expect(roomService.sentMessages.count == 1)
    #expect(roomService.sentMessages.first?.body == "Hello!")
}

@Test func emptyMessageNotSent() async {
    let roomService = MockRoomService()
    let vm = await TimelineViewModel(roomID: "!room:x", roomService: roomService)

    await vm.sendMessage("")
    await vm.sendMessage("   ")

    #expect(roomService.sentMessages.isEmpty)
}

@Test func receivesTypingUsers() async throws {
    let roomService = MockRoomService()
    let typingService = MockTypingService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: roomService,
        typingService: typingService,
        currentUserID: "@me:x"
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
    let roomService = MockRoomService()
    let typingService = MockTypingService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: roomService,
        typingService: typingService,
        currentUserID: "@me:x"
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
    let roomService = MockRoomService()
    let typingService = MockTypingService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: roomService,
        typingService: typingService,
        currentUserID: "@me:x"
    )

    await vm.onComposerChanged(text: "Hello")

    try await Task.sleep(for: .milliseconds(50))

    #expect(typingService.typingNotices.contains { $0.roomID == "!room:x" && $0.isTyping == true })
}

@Test func sendsStopTypingOnSend() async throws {
    let roomService = MockRoomService()
    let typingService = MockTypingService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: roomService,
        typingService: typingService,
        currentUserID: "@me:x"
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
    let roomService = MockRoomService()
    let typingService = MockTypingService()
    let vm = await TimelineViewModel(
        roomID: "!room:x",
        roomService: roomService,
        typingService: typingService,
        currentUserID: "@me:x"
    )

    await vm.onComposerChanged(text: "")

    try await Task.sleep(for: .milliseconds(50))

    #expect(typingService.typingNotices.isEmpty)
}
