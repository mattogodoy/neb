import Foundation
import NebCore
import os

private let logger = Logger(subsystem: "com.neb.app", category: "AppState")

@MainActor
@Observable
final class AppState {
    let session: Session
    let syncAdapter: MatrixSyncAdapter
    let roomAdapter: Room
    let cryptoAdapter: MatrixCryptoAdapter
    let notificationAdapter: MatrixNotificationAdapter
    let typingAdapter: MatrixTypingAdapter

    private(set) var loginViewModel: LoginViewModel
    private(set) var roomListViewModel: RoomListViewModel?
    private(set) var deviceVerificationStatus: DeviceVerificationStatus = .unknown

    init() {
        let session = Session()
        let sync = MatrixSyncAdapter(clientProvider: { session.getClient() })
        let room = Room(clientProvider: { session.getClient() }, roomListServiceProvider: { sync.roomListService })
        let crypto = MatrixCryptoAdapter(clientProvider: { session.getClient() })
        let notification = MatrixNotificationAdapter()
        let typing = MatrixTypingAdapter(clientProvider: { session.getClient() }, roomListServiceProvider: { sync.roomListService })

        self.session = session
        self.syncAdapter = sync
        self.roomAdapter = room
        self.cryptoAdapter = crypto
        self.notificationAdapter = notification
        self.typingAdapter = typing
        self.loginViewModel = LoginViewModel(auth: session, session: session)
    }

    func onLoggedIn() async {
        AvatarImageCache.shared.setClientProvider { [weak self] in self?.session.getClient() }
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

    var homeserverURL: String {
        session.cachedHomeserverURL ?? ""
    }

    func makeRoomService() -> any RoomProtocol { roomAdapter }
    func makeCryptoService() -> any CryptoProtocol { cryptoAdapter }
    func makeTypingService() -> any TypingProtocol { typingAdapter }

    var currentUserID: String? {
        session.cachedUserID
    }
}
