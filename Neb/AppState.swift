import Foundation
import NebCore

@MainActor
@Observable
final class AppState {
    let authAdapter: MatrixAuthAdapter
    let syncAdapter: MatrixSyncAdapter
    let roomAdapter: MatrixRoomAdapter
    let cryptoAdapter: MatrixCryptoAdapter
    let notificationAdapter: MatrixNotificationAdapter

    private(set) var loginViewModel: LoginViewModel
    private(set) var roomListViewModel: RoomListViewModel?
    private(set) var deviceVerificationStatus: DeviceVerificationStatus = .unknown

    init() {
        let auth = MatrixAuthAdapter()
        let sync = MatrixSyncAdapter(clientProvider: { auth.getClient() })
        let room = MatrixRoomAdapter(clientProvider: { auth.getClient() }, roomListServiceProvider: { sync.roomListService })
        let crypto = MatrixCryptoAdapter(clientProvider: { auth.getClient() })
        let notification = MatrixNotificationAdapter()

        self.authAdapter = auth
        self.syncAdapter = sync
        self.roomAdapter = room
        self.cryptoAdapter = crypto
        self.notificationAdapter = notification
        self.loginViewModel = LoginViewModel(authService: auth)
    }

    func onLoggedIn() async {
        roomListViewModel = RoomListViewModel(
            syncService: syncAdapter,
            notificationService: notificationAdapter
        )
        let _ = try? await notificationAdapter.requestPermission()
        try? await syncAdapter.startSync()
        try? await cryptoAdapter.setupVerificationListener()

        Task { [weak self] in
            guard let self else { return }
            for await status in self.cryptoAdapter.deviceVerificationStatusStream() {
                self.deviceVerificationStatus = status
            }
        }
    }

    func onLoggedOut() async {
        try? await syncAdapter.stopSync()
        roomListViewModel = nil
        deviceVerificationStatus = .unknown
    }

    var homeserverURL: String { "https://matrix.matto.io" }

    func makeRoomService() -> any RoomServiceProtocol { roomAdapter }
    func makeCryptoService() -> any CryptoServiceProtocol { cryptoAdapter }
}
