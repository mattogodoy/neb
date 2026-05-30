import Foundation
import NebCore
import os

private let logger = Logger(subsystem: "com.neb.app", category: "AppState")

@MainActor
@Observable
final class AppState {
    let session: Session
    let sync: Sync
    let roomAdapter: Room
    let devicesAdapter: Devices
    let securityAdapter: Security
    let notificationAdapter: Notification
    let database: NebDatabase
    let backfillWorker: BackfillWorker

    private(set) var loginViewModel: LoginViewModel
    private(set) var roomListViewModel: RoomListViewModel?
    private(set) var deviceVerificationStatus: DeviceVerificationStatus = .unknown
    private(set) var isOnline: Bool = false
    @ObservationIgnored nonisolated(unsafe) private var syncTask: Task<Void, Never>?

    init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Neb", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let dbPath = supportDir.appendingPathComponent("neb.db").path
        let database = try! NebDatabase(path: dbPath)

        let session = Session()
        let sync = Sync(clientProvider: { session.getClient() }, database: database)
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
        self.sync = sync
        self.roomAdapter = room
        self.devicesAdapter = devices
        self.securityAdapter = security
        self.notificationAdapter = notification
        self.backfillWorker = backfill
        self.loginViewModel = LoginViewModel(auth: session, session: session)
    }

    func onLoggedIn() async {
        AvatarImageCache.shared.setClientProvider { [weak self] in self?.session.getClient() }
        roomListViewModel = RoomListViewModel(
            roomService: roomAdapter,
            notificationService: notificationAdapter
        )
        do { let _ = try await notificationAdapter.requestPermission() } catch { logger.error("Failed to request notification permission: \(error)") }

        // Sync connects in the background — UI is already showing cached data
        syncTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sync.start()
            } catch {
                logger.error("Failed to start sync: \(error)")
            }
        }

        Task { [weak self] in
            guard let self else { return }
            var hasSetupVerification = false
            var hasStartedBackfill = false
            for await online in self.sync.statusStream() {
                self.isOnline = online
                if online {
                    if !hasSetupVerification {
                        hasSetupVerification = true
                        do { try await self.securityAdapter.setupVerificationListener() } catch { logger.error("Failed to setup verification listener: \(error)") }
                    }
                    if !hasStartedBackfill {
                        hasStartedBackfill = true
                        for await rooms in self.roomAdapter.roomListStream() {
                            let roomIDs = rooms.map { $0.id }
                            self.backfillWorker.start(roomIDs: roomIDs)
                            break
                        }
                    }
                }
            }
        }

        Task { [weak self] in
            guard let self else { return }
            for await status in self.devicesAdapter.verificationStatusStream() {
                self.deviceVerificationStatus = status
            }
        }
    }

    func onLoggedOut() async {
        backfillWorker.stop()
        syncTask?.cancel()
        syncTask = nil
        do { try await sync.stop() } catch { logger.error("Failed to stop sync: \(error)") }
        roomListViewModel = nil
        deviceVerificationStatus = .unknown
        isOnline = false
    }

    var homeserverURL: String {
        session.cachedHomeserverURL ?? ""
    }

    func makeTimelineService() -> any TimelineProtocol { roomAdapter }
    func makeRoomsService() -> any RoomsProtocol { roomAdapter }
    func makeMembersService() -> any MembersProtocol { roomAdapter }
    func makeSecurityService() -> any SecurityProtocol { securityAdapter }
    func makeTypingService() -> any TypingProtocol { roomAdapter }
    func makeSyncService() -> any SyncProtocol { sync }

    var currentUserID: String? {
        session.cachedUserID
    }
}
