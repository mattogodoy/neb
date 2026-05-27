import Foundation
import Testing
@testable import Neb
import NebCore

@Test func createDMSuccess() async throws {
    let roomService = MockRoomService()
    let vm = await NewDMViewModel(roomService: roomService)

    await vm.setUserID("@alice:example.com")
    let roomID = await vm.createDM()

    #expect(roomID == "!new-dm-room:example.com")
    #expect(roomService.createdDMUserID == "@alice:example.com")
}

@Test func emptyUserIDDisablesCreate() async {
    let roomService = MockRoomService()
    let vm = await NewDMViewModel(roomService: roomService)
    let canCreate = await vm.canCreate
    #expect(!canCreate)
}

@Test func validUserIDEnablesCreate() async {
    let roomService = MockRoomService()
    let vm = await NewDMViewModel(roomService: roomService)
    await vm.setUserID("@alice:example.com")
    let canCreate = await vm.canCreate
    #expect(canCreate)
}

@Test func invalidUserIDFormat() async {
    let roomService = MockRoomService()
    let vm = await NewDMViewModel(roomService: roomService)
    await vm.setUserID("alice")
    let canCreate = await vm.canCreate
    #expect(!canCreate)
}
