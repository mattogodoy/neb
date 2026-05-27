import SwiftUI
import NebCore

struct MainView: View {
    @Bindable var roomListViewModel: RoomListViewModel
    let roomServiceProvider: () -> any RoomProtocol
    var cryptoServiceProvider: (() -> any CryptoProtocol)?
    var typingServiceProvider: (() -> any TypingProtocol)?
    var currentUserID: String?
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
                    cryptoServiceProvider: cryptoServiceProvider,
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
            if let newID {
                let room = roomListViewModel.allRooms.first { $0.id == newID }
                timelineViewModel = TimelineViewModel(
                    roomID: newID,
                    roomService: roomServiceProvider(),
                    typingService: typingServiceProvider?(),
                    currentUserID: currentUserID,
                    initialUnreadCount: room?.unreadCount ?? 0
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
        .sheet(isPresented: $showDeviceVerification) {
            if let provider = cryptoServiceProvider {
                DeviceVerificationView(
                    viewModel: VerificationViewModel(cryptoService: provider()),
                    isAlreadyVerified: deviceVerificationStatus == .verified,
                    cryptoService: provider()
                )
            }
        }
    }
}
