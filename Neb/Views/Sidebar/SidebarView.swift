import SwiftUI
import NebCore

struct SidebarView: View {
    @Bindable var viewModel: RoomListViewModel
    var homeserverURL: String = ""
    var onNewDM: () -> Void
    var onNewRoom: () -> Void

    @State private var dmSectionExpanded = true
    @State private var groupSectionExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(8)

            List(selection: Binding(
                get: { viewModel.selectedRoom?.id },
                set: { id in
                    viewModel.selectRoom(
                        viewModel.allRooms.first { $0.id == id }
                    )
                }
            )) {
                Section(isExpanded: $dmSectionExpanded) {
                    ForEach(viewModel.directMessages) { room in
                        RoomRowView(
                            room: room,
                            homeserverURL: homeserverURL,
                            typingUsers: viewModel.typingUsers(for: room.id)
                        )
                        .tag(room.id)
                    }
                } header: {
                    Text("Direct Messages")
                }

                Section(isExpanded: $groupSectionExpanded) {
                    ForEach(viewModel.groups) { room in
                        RoomRowView(
                            room: room,
                            homeserverURL: homeserverURL,
                            typingUsers: viewModel.typingUsers(for: room.id)
                        )
                        .tag(room.id)
                    }
                } header: {
                    Text("Groups")
                }
            }
            .listStyle(.sidebar)
        }
        .toolbar {
            ToolbarItem {
                Button(action: onNewRoom) {
                    Image(systemName: "plus.bubble")
                }
                .help("New Room")
            }
            ToolbarItem {
                Button(action: onNewDM) {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Direct Message")
            }
        }
    }
}
