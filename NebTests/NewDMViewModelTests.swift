import Foundation
import Testing
@testable import Neb
import NebCore

@Test func createDMSuccess() async throws {
    let roomsService = MockRoomsService()
    let vm = await NewDMViewModel(roomService: roomsService)

    await vm.setUserID("@alice:example.com")
    let roomID = await vm.createDM()

    #expect(roomID == "!new-dm-room:example.com")
    #expect(roomsService.createdDMUserID == "@alice:example.com")
}

@Test func emptyUserIDDisablesCreate() async {
    let roomsService = MockRoomsService()
    let vm = await NewDMViewModel(roomService: roomsService)
    let canCreate = await vm.canCreate
    #expect(!canCreate)
}

@Test func validUserIDEnablesCreate() async {
    let roomsService = MockRoomsService()
    let vm = await NewDMViewModel(roomService: roomsService)
    await vm.setUserID("@alice:example.com")
    let canCreate = await vm.canCreate
    #expect(canCreate)
}

@Test func invalidUserIDFormat() async {
    let roomsService = MockRoomsService()
    let vm = await NewDMViewModel(roomService: roomsService)
    await vm.setUserID("alice")
    let canCreate = await vm.canCreate
    #expect(!canCreate)
}
