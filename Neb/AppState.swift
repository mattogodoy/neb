import Foundation
import NebCore
import os

private let logger = Logger(subsystem: "com.neb.app", category: "AppState")

@MainActor
@Observable
final class AppState {
    let authAdapter: Auth
    let syncAdapter: MatrixSyncAdapter
    let roomAdapter: MatrixRoomAdapter
    let cryptoAdapter: MatrixCryptoAdapter
    let notificationAdapter: MatrixNotificationAdapter
    let typingAdapter: MatrixTypingAdapter

    private(set) var loginViewModel: LoginViewModel
    private(set) var roomListViewModel: RoomListViewModel?
    private(set) var deviceVerificationStatus: DeviceVerificationStatus = .unknown

    init() {
        let auth = Auth()
        let sync = MatrixSyncAdapter(clientProvider: { auth.getClient() })
        let room = MatrixRoomAdapter(clientProvider: { auth.getClient() }, roomListServiceProvider: { sync.roomListService })
        let crypto = MatrixCryptoAdapter(clientProvider: { auth.getClient() })
        let notification = MatrixNotificationAdapter()
        let typing = MatrixTypingAdapter(clientProvider: { auth.getClient() }, roomListServiceProvider: { sync.roomListService })

        self.authAdapter = auth
        self.syncAdapter = sync
        self.roomAdapter = room
        self.cryptoAdapter = crypto
        self.notificationAdapter = notification
        self.typingAdapter = typing
        self.loginViewModel = LoginViewModel(authService: auth)
    }

    func onLoggedIn() async {
        AvatarImageCache.shared.setClientProvider { [weak self] in self?.authAdapter.getClient() }
        roomListViewModel = RoomListViewModel(
            syncService: syncAdapter,
            notificationService: notificationAdapter,
            typingService: typingAdapter
        )
        do { let _ = try await notificationAdapter.requestPermission() } catch { logger.error("Failed to request notification permission: \(error)") }
        do { try await syncAdapter.startSync() } catch { logger.error("Failed to start sync: \(error)") }
        do { try await cryptoAdapter.setupVerificationListener() } catch { logger.error("Failed to setup verification listener: \(error)") }

        Task { [weak self] in
            guard let self else { return }
            for await status in self.cryptoAdapter.deviceVerificationStatusStream() {
                self.deviceVerificationStatus = status
            }
        }
    }

    func onLoggedOut() async {
        do { try await syncAdapter.stopSync() } catch { logger.error("Failed to stop sync: \(error)") }
        roomListViewModel = nil
        deviceVerificationStatus = .unknown
    }

    var homeserverURL: String { "https://matrix.matto.io" }

    func makeRoomService() -> any RoomServiceProtocol { roomAdapter }
    func makeCryptoService() -> any CryptoServiceProtocol { cryptoAdapter }
    func makeTypingService() -> any TypingServiceProtocol { typingAdapter }

    var currentUserID: String? {
        try? authAdapter.getClient()?.userId()
    }
}
