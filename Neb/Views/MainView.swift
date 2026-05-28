import SwiftUI
import NebCore

struct MainView: View {
    @Bindable var roomListViewModel: RoomListViewModel
    let timelineServiceProvider: () -> any TimelineProtocol
    var roomsServiceProvider: (() -> any RoomsProtocol)?
    var securityServiceProvider: (() -> any SecurityProtocol)?
    var typingServiceProvider: (() -> any TypingProtocol)?
    var syncServiceProvider: (() -> any SyncProtocol)?
    var currentUserID: String?
    var database: NebDatabase?
    var deviceVerificationStatus: DeviceVerificationStatus = .unknown
    var homeserverURL: String = ""
    var onLogout: (() -> Void)?
    @State private var showNewDM = false
    @State private var showDeviceVerification = false
    @State private var showLogoutConfirmation = false
    @State private var timelineViewModel: TimelineViewModel?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: roomListViewModel,
                homeserverURL: homeserverURL,
                onNewDM: { showNewDM = true }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let room = roomListViewModel.selectedRoom,
               let vm = timelineViewModel {
                TimelineView(
                    viewModel: vm,
                    roomName: room.name,
                    directUserID: room.directUserID,
                    securityServiceProvider: securityServiceProvider,
                    isDM: room.isDirect,
                    homeserverURL: homeserverURL
                )
                .id(room.id)
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a conversation from the sidebar.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showDeviceVerification = true }) {
                    Label(
                        deviceVerificationStatus == .verified ? "Device Verified" : "Verify Device",
                        systemImage: deviceVerificationStatus == .verified ? "lock.shield.fill" : "lock.shield"
                    )
                    .foregroundStyle(deviceVerificationStatus == .verified ? .green : .orange)
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button(role: .destructive, action: { showLogoutConfirmation = true }) {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .alert("Log Out", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Log Out", role: .destructive) { onLogout?() }
        } message: {
            Text("You'll need to log in again and re-verify this device.")
        }
        .onChange(of: roomListViewModel.selectedRoom?.id) { _, newID in
            if let newID, let db = database {
                let room = roomListViewModel.allRooms.first { $0.id == newID }
                timelineViewModel = TimelineViewModel(
                    roomID: newID,
                    roomService: timelineServiceProvider(),
                    database: db,
                    currentUserID: currentUserID ?? "",
                    typingService: typingServiceProvider?(),
                    syncService: syncServiceProvider?(),
                    initialUnreadCount: room?.unreadCount ?? 0
                )
            } else {
                timelineViewModel = nil
            }
        }
        .sheet(isPresented: $showNewDM) {
            NewDMSheet(
                viewModel: NewDMViewModel(roomService: roomsServiceProvider!()),
                onCreated: { roomID in
                    if let room = roomListViewModel.allRooms.first(where: { $0.id == roomID }) {
                        roomListViewModel.selectRoom(room)
                    }
                }
            )
        }
        .sheet(isPresented: $showDeviceVerification) {
            if let provider = securityServiceProvider {
                DeviceVerificationView(
                    viewModel: VerificationViewModel(securityService: provider()),
                    isAlreadyVerified: deviceVerificationStatus == .verified,
                    securityService: provider()
                )
            }
        }
    }
}
