import SwiftUI
import NebCore

struct MainView: View {
    @Bindable var roomListViewModel: RoomListViewModel
    let roomServiceProvider: () -> any RoomServiceProtocol
    var cryptoServiceProvider: (() -> any CryptoServiceProtocol)?
    @State private var showNewDM = false
    @State private var timelineViewModel: TimelineViewModel?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: roomListViewModel,
                onNewDM: { showNewDM = true }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let room = roomListViewModel.selectedRoom,
               let vm = timelineViewModel {
                TimelineView(
                    viewModel: vm,
                    roomName: room.name,
                    cryptoServiceProvider: cryptoServiceProvider
                )
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a conversation from the sidebar.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onChange(of: roomListViewModel.selectedRoom?.id) { _, newID in
            if let newID {
                timelineViewModel = TimelineViewModel(
                    roomID: newID,
                    roomService: roomServiceProvider()
                )
            } else {
                timelineViewModel = nil
            }
        }
        .sheet(isPresented: $showNewDM) {
            NewDMSheet(
                viewModel: NewDMViewModel(roomService: roomServiceProvider()),
                onCreated: { roomID in
                    if let room = roomListViewModel.allRooms.first(where: { $0.id == roomID }) {
                        roomListViewModel.selectRoom(room)
                    }
                }
            )
        }
    }
}
