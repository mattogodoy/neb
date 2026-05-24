import SwiftUI
import NebCore

struct MainView: View {
    @Bindable var roomListViewModel: RoomListViewModel
    @State private var showNewDM = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: roomListViewModel,
                onNewDM: { showNewDM = true }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let room = roomListViewModel.selectedRoom {
                Text("Timeline for \(room.name)")
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a conversation from the sidebar.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $showNewDM) {
            Text("New DM (placeholder)")
                .frame(width: 300, height: 200)
        }
    }
}
