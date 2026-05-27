import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Auth")

public final class Auth: AuthServiceProtocol, @unchecked Sendable {
    private var client: Client?
    private var _authState: AuthState = .loggedOut
    private var continuation: AsyncStream<AuthState>.Continuation?

    private let sessionDirectory: URL
    private let keychain: KeychainController

    public init(keychain: KeychainController = KeychainController()) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        sessionDirectory = appSupport.appendingPathComponent("Neb", isDirectory: true)
        self.keychain = keychain
        try? FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        // Clean break: if old session.json exists, wipe everything
        let oldSessionFile = sessionDirectory.appendingPathComponent("session.json")
        if FileManager.default.fileExists(atPath: oldSessionFile.path) {
            logger.info("Found legacy session.json, wiping old storage for clean migration")
            clearLocalData()
        }
    }

    public var authState: AuthState {
        get async { _authState }
    }

    public func login(homeserverURL: String, username: String, password: String) async throws {
        setState(.loggingIn)
        logger.info("Logging in to \(homeserverURL) as \(username)")

        let dataPath = sessionDirectory.appendingPathComponent("data").path
        let cachePath = sessionDirectory.appendingPathComponent("cache").path

        // Generate passphrase for crypto store
        let passphrase = generatePassphrase()

        do {
            var t = ContinuousClock.now
            let storeConfig = SqliteStoreBuilder(dataPath: dataPath, cachePath: cachePath)
                .passphrase(passphrase: passphrase)

            let client = try await ClientBuilder()
                .serverNameOrHomeserverUrl(serverNameOrUrl: homeserverURL)
                .sqliteStore(config: storeConfig)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .autoEnableCrossSigning(autoEnableCrossSigning: true)
                .autoEnableBackups(autoEnableBackups: true)
                .build()
            logger.info("ClientBuilder.build() took \(ContinuousClock.now - t)")

            t = ContinuousClock.now
            try await client.login(
                username: username,
                password: password,
                initialDeviceName: "Neb macOS",
                deviceId: nil
            )
            logger.info("client.login() took \(ContinuousClock.now - t)")

            self.client = client

            let sdkSession = try client.session()
            let userID = try client.userId()

            let nebSession = NebSession(
                accessToken: sdkSession.accessToken,
                userId: sdkSession.userId,
                deviceId: sdkSession.deviceId,
                homeserverUrl: sdkSession.homeserverUrl,
                slidingSyncVersion: sdkSession.slidingSyncVersion == .native ? "native" : "none",
                refreshToken: sdkSession.refreshToken,
                oauthData: sdkSession.oauthData
            )

            try keychain.saveSession(nebSession, for: userID)
            try keychain.savePassphrase(passphrase, for: userID)

            logger.info("Login successful: \(userID)")
            setState(.loggedIn(userID: userID))
        } catch {
            logger.error("Login failed: \(error.localizedDescription), clearing stores")
            clearLocalData()
            throw error
        }
    }

    public func restoreSession() async throws -> Bool {
        guard let lastUserID = UserDefaults.standard.string(forKey: "com.neb.lastUserID"),
              let session = keychain.loadSession(for: lastUserID),
              let passphrase = keychain.loadPassphrase(for: lastUserID) else {
            logger.info("No session to restore from Keychain")
            return false
        }

        logger.info("Restoring session for \(session.userId) on \(session.homeserverUrl)")

        let slidingSyncVersion: SlidingSyncVersion = session.slidingSyncVersion == "native" ? .native : .none

        let sdkSession = Session(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            userId: session.userId,
            deviceId: session.deviceId,
            homeserverUrl: session.homeserverUrl,
            oauthData: session.oauthData,
            slidingSyncVersion: slidingSyncVersion
        )

        let dataPath = sessionDirectory.appendingPathComponent("data").path
        let cachePath = sessionDirectory.appendingPathComponent("cache").path

        do {
            let storeConfig = SqliteStoreBuilder(dataPath: dataPath, cachePath: cachePath)
                .passphrase(passphrase: passphrase)

            let t = ContinuousClock.now
            let client = try await ClientBuilder()
                .serverNameOrHomeserverUrl(serverNameOrUrl: session.homeserverUrl)
                .sqliteStore(config: storeConfig)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .build()
            logger.info("Restore: build() took \(ContinuousClock.now - t)")

            let t2 = ContinuousClock.now
            try await client.restoreSession(session: sdkSession)
            logger.info("Restore: restoreSession() took \(ContinuousClock.now - t2)")

            self.client = client
            let userID = try client.userId()
            logger.info("Session restored: \(userID)")
            setState(.loggedIn(userID: userID))
            return true
        } catch {
            logger.error("Session restore failed: \(error.localizedDescription), clearing stale data")
            keychain.deleteAll(for: lastUserID)
            clearLocalData()
            return false
        }
    }

    public func logout() async throws {
        let userID = try? client?.userId()
        try await client?.logout()
        client = nil
        if let userID {
            keychain.deleteAll(for: userID)
            UserDefaults.standard.removeObject(forKey: "com.neb.lastUserID")
        }
        clearLocalData()
        logger.info("Logged out and cleared session data")
        setState(.loggedOut)
    }

    public func authStateStream() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(self._authState)
        }
    }

    public func getClient() -> Client? { client }

    // MARK: - Private

    private func setState(_ state: AuthState) {
        _authState = state
        continuation?.yield(state)

        if case .loggedIn(let userID) = state {
            UserDefaults.standard.set(userID, forKey: "com.neb.lastUserID")
        }
    }

    private func clearLocalData() {
        try? FileManager.default.removeItem(at: sessionDirectory.appendingPathComponent("data"))
        try? FileManager.default.removeItem(at: sessionDirectory.appendingPathComponent("cache"))
        try? FileManager.default.removeItem(at: sessionDirectory.appendingPathComponent("session.json"))
    }

    private func generatePassphrase() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<32).map { _ in chars.randomElement()! })
    }
}
