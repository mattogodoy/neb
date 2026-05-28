import Foundation
import Testing
@testable import Neb
import NebCore

@Test func initialStateIsEmpty() async {
    let roomService = MockRoomsService()
    let vm = await RoomListViewModel(roomService: roomService)
    let dms = await vm.directMessages
    let groups = await vm.groups
    #expect(dms.isEmpty)
    #expect(groups.isEmpty)
}

@Test func roomsSplitByType() async throws {
    let roomService = MockRoomsService()
    let vm = await RoomListViewModel(roomService: roomService)

    let dm = NebRoom(id: "!dm:example.com", name: "Alice", isDirect: true)
    let group = NebRoom(id: "!group:example.com", name: "Work Chat", isDirect: false)
    roomService.emitRooms([dm, group])

    try await Task.sleep(for: .milliseconds(50))

    let dms = await vm.directMessages
    let groups = await vm.groups
    #expect(dms.count == 1)
    #expect(dms.first?.name == "Alice")
    #expect(groups.count == 1)
    #expect(groups.first?.name == "Work Chat")
}

@Test func totalUnreadCount() async throws {
    let roomService = MockRoomsService()
    let vm = await RoomListViewModel(roomService: roomService)

    roomService.emitRooms([
        NebRoom(id: "!a:x", name: "A", unreadCount: 3, isDirect: true),
        NebRoom(id: "!b:x", name: "B", unreadCount: 5, isDirect: false),
    ])

    try await Task.sleep(for: .milliseconds(50))

    let total = await vm.totalUnreadCount
    #expect(total == 8)
}

@Test func selectRoom() async {
    let roomService = MockRoomsService()
    let vm = await RoomListViewModel(roomService: roomService)
    let room = NebRoom(id: "!room:x", name: "Test")

    await vm.selectRoom(room)

    let selected = await vm.selectedRoom
    #expect(selected?.id == "!room:x")
}

@Test func searchFiltersRooms() async throws {
    let roomService = MockRoomsService()
    let vm = await RoomListViewModel(roomService: roomService)

    roomService.emitRooms([
        NebRoom(id: "!a:x", name: "Alice", isDirect: true),
        NebRoom(id: "!b:x", name: "Bob", isDirect: true),
        NebRoom(id: "!c:x", name: "Work Chat", isDirect: false),
    ])

    try await Task.sleep(for: .milliseconds(50))

    await vm.setSearchQuery("ali")

    let dms = await vm.directMessages
    let groups = await vm.groups
    #expect(dms.count == 1)
    #expect(dms.first?.name == "Alice")
    #expect(groups.isEmpty)
}

@Test func tracksTypingUsersPerRoom() async throws {
    let roomService = MockRoomsService()
    let vm = await RoomListViewModel(roomService: roomService)

    roomService.emitRooms([
        NebRoom(id: "!room:x", name: "Alice", isDirect: true),
    ])

    try await Task.sleep(for: .milliseconds(50))

    let alice = NebUser(id: "@alice:x", displayName: "Alice")
    roomService.emitTypingUsers(roomID: "!room:x", users: [alice])

    try await Task.sleep(for: .milliseconds(50))

    let typing = await vm.typingUsers(for: "!room:x")
    #expect(typing.count == 1)
    #expect(typing.first?.id == "@alice:x")
}

@Test func typingUsersClearWhenEmpty() async throws {
    let roomService = MockRoomsService()
    let vm = await RoomListViewModel(roomService: roomService)

    roomService.emitRooms([
        NebRoom(id: "!room:x", name: "Alice", isDirect: true),
    ])

    try await Task.sleep(for: .milliseconds(50))

    let alice = NebUser(id: "@alice:x", displayName: "Alice")
    roomService.emitTypingUsers(roomID: "!room:x", users: [alice])
    try await Task.sleep(for: .milliseconds(50))

    roomService.emitTypingUsers(roomID: "!room:x", users: [])
    try await Task.sleep(for: .milliseconds(50))

    let typing = await vm.typingUsers(for: "!room:x")
    #expect(typing.isEmpty)
}
