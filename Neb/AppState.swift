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
    let devicesAdapter: Devices
    let securityAdapter: Security
    let notificationAdapter: Notification
    let database: NebDatabase
    let backfillWorker: BackfillWorker

    private(set) var loginViewModel: LoginViewModel
    private(set) var roomListViewModel: RoomListViewModel?
    private(set) var deviceVerificationStatus: DeviceVerificationStatus = .unknown

    init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Neb", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let dbPath = supportDir.appendingPathComponent("neb.db").path
        let database = try! NebDatabase(path: dbPath)

        let session = Session()
        let sync = MatrixSyncAdapter(clientProvider: { session.getClient() })
        let room = Room(clientProvider: { session.getClient() }, roomListServiceProvider: { sync.roomListService }, database: database)
        let devices = Devices(clientProvider: { session.getClient() })
        let security = Security(clientProvider: { session.getClient() })
        let notification = Notification()
        let backfill = BackfillWorker(
            clientProvider: { session.getClient() },
            roomListServiceProvider: { sync.roomListService },
            database: database
        )

        self.database = database
        self.session = session
        self.syncAdapter = sync
        self.roomAdapter = room
        self.devicesAdapter = devices
        self.securityAdapter = security
        self.notificationAdapter = notification
        self.backfillWorker = backfill
        self.loginViewModel = LoginViewModel(auth: session, session: session)
    }

    func onLoggedIn() async {
        do { try database.failStalePendingMessages() } catch { logger.error("Failed to clean pending messages: \(error)") }
        AvatarImageCache.shared.setClientProvider { [weak self] in self?.session.getClient() }
        roomListViewModel = RoomListViewModel(
            syncService: syncAdapter,
            notificationService: notificationAdapter,
            typingService: roomAdapter
        )
        do { let _ = try await notificationAdapter.requestPermission() } catch { logger.error("Failed to request notification permission: \(error)") }
        do { try await syncAdapter.startSync() } catch { logger.error("Failed to start sync: \(error)") }
        do { try await securityAdapter.setupVerificationListener() } catch { logger.error("Failed to setup verification listener: \(error)") }

        Task { [weak self] in
            guard let self else { return }
            for await status in self.devicesAdapter.verificationStatusStream() {
                self.deviceVerificationStatus = status
            }
        }

        Task { [weak self] in
            guard let self else { return }
            // Wait for the first room list emission then start the backfill worker
            for await rooms in self.syncAdapter.roomListStream() {
                let roomIDs = rooms.map { $0.id }
                self.backfillWorker.start(roomIDs: roomIDs)
                break
            }
        }
    }

    func onLoggedOut() async {
        backfillWorker.stop()
        do { try await syncAdapter.stopSync() } catch { logger.error("Failed to stop sync: \(error)") }
        roomListViewModel = nil
        deviceVerificationStatus = .unknown
    }

    var homeserverURL: String {
        session.cachedHomeserverURL ?? ""
    }

    func makeTimelineService() -> any TimelineProtocol { roomAdapter }
    func makeRoomsService() -> any RoomsProtocol { roomAdapter }
    func makeMembersService() -> any MembersProtocol { roomAdapter }
    func makeSecurityService() -> any SecurityProtocol { securityAdapter }
    func makeTypingService() -> any TypingProtocol { roomAdapter }

    var currentUserID: String? {
        session.cachedUserID
    }
}
