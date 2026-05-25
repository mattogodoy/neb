import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Auth")

public final class MatrixAuthAdapter: AuthServiceProtocol, @unchecked Sendable {
    private var client: Client?
    private var _authState: AuthState = .loggedOut
    private var continuation: AsyncStream<AuthState>.Continuation?

    private let sessionDirectory: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        sessionDirectory = appSupport.appendingPathComponent("Neb", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
    }

    public var authState: AuthState {
        get async { _authState }
    }

    public func login(homeserverURL: String, username: String, password: String) async throws {
        setState(.loggingIn)

        // Only clear the session token, keep crypto/state stores for fast re-login
        try? FileManager.default.removeItem(at: sessionDirectory.appendingPathComponent("session.json"))
        logger.info("Logging in to \(homeserverURL) as \(username)")

        let dataPath = sessionDirectory.appendingPathComponent("data").path
        let cachePath = sessionDirectory.appendingPathComponent("cache").path

        do {
            var t = ContinuousClock.now
            let client = try await ClientBuilder()
                .serverNameOrHomeserverUrl(serverNameOrUrl: homeserverURL)
                .sessionPaths(dataPath: dataPath, cachePath: cachePath)
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
            try persistSession(from: client)
            let userID = try client.userId()
            logger.info("Login successful: \(userID)")
            setState(.loggedIn(userID: userID))
        } catch {
            // Crypto store conflict — clear everything and let user retry
            logger.error("Login failed: \(error.localizedDescription), clearing stores")
            clearSessionData()
            throw error
        }
    }

    public func restoreSession() async throws -> Bool {
        let sessionFile = sessionDirectory.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: sessionFile.path) else {
            logger.info("No session to restore")
            return false
        }

        let sessionData = try Data(contentsOf: sessionFile)
        guard let dict = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any] else { return false }

        guard
            let accessToken = dict["accessToken"] as? String,
            let userId = dict["userId"] as? String,
            let deviceId = dict["deviceId"] as? String,
            let homeserverUrl = dict["homeserverUrl"] as? String,
            let slidingSyncVersionRaw = dict["slidingSyncVersion"] as? String
        else { return false }

        logger.info("Restoring session for \(userId) on \(homeserverUrl)")

        let slidingSyncVersion: SlidingSyncVersion = slidingSyncVersionRaw == "native" ? .native : .none
        let refreshToken = dict["refreshToken"] as? String
        let oauthData = dict["oauthData"] as? String

        let session = Session(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId,
            deviceId: deviceId,
            homeserverUrl: homeserverUrl,
            oauthData: oauthData,
            slidingSyncVersion: slidingSyncVersion
        )

        let dataPath = sessionDirectory.appendingPathComponent("data").path
        let cachePath = sessionDirectory.appendingPathComponent("cache").path

        do {
            let t = ContinuousClock.now
            let client = try await ClientBuilder()
                .serverNameOrHomeserverUrl(serverNameOrUrl: homeserverUrl)
                .sessionPaths(dataPath: dataPath, cachePath: cachePath)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .build()
            logger.info("Restore: build() took \(ContinuousClock.now - t)")

            let t2 = ContinuousClock.now
            try await client.restoreSession(session: session)
            logger.info("Restore: restoreSession() took \(ContinuousClock.now - t2)")

            self.client = client
            let userID = try client.userId()
            logger.info("Session restored: \(userID)")
            setState(.loggedIn(userID: userID))
            return true
        } catch {
            logger.error("Session restore failed: \(error.localizedDescription), clearing stale data")
            clearSessionData()
            return false
        }
    }

    public func logout() async throws {
        try await client?.logout()
        client = nil
        clearSessionData()
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

    private func setState(_ state: AuthState) {
        _authState = state
        continuation?.yield(state)
    }

    private func clearSessionData() {
        try? FileManager.default.removeItem(at: sessionDirectory.appendingPathComponent("data"))
        try? FileManager.default.removeItem(at: sessionDirectory.appendingPathComponent("cache"))
        try? FileManager.default.removeItem(at: sessionDirectory.appendingPathComponent("session.json"))
    }

    private func persistSession(from client: Client) throws {
        let session = try client.session()
        let slidingSyncVersionStr: String
        switch session.slidingSyncVersion {
        case .native: slidingSyncVersionStr = "native"
        case .none: slidingSyncVersionStr = "none"
        }
        var dict: [String: Any] = [
            "accessToken": session.accessToken,
            "userId": session.userId,
            "deviceId": session.deviceId,
            "homeserverUrl": session.homeserverUrl,
            "slidingSyncVersion": slidingSyncVersionStr
        ]
        if let refreshToken = session.refreshToken {
            dict["refreshToken"] = refreshToken
        }
        if let oauthData = session.oauthData {
            dict["oauthData"] = oauthData
        }
        let data = try JSONSerialization.data(withJSONObject: dict)
        let sessionFile = sessionDirectory.appendingPathComponent("session.json")
        try data.write(to: sessionFile)
    }
}
