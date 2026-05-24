import Foundation
import MatrixRustSDK

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

        let dataPath = sessionDirectory.appendingPathComponent("data").path
        let cachePath = sessionDirectory.appendingPathComponent("cache").path

        let client = try await ClientBuilder()
            .serverNameOrHomeserverUrl(serverNameOrUrl: homeserverURL)
            .sessionPaths(dataPath: dataPath, cachePath: cachePath)
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .autoEnableCrossSigning(autoEnableCrossSigning: true)
            .autoEnableBackups(autoEnableBackups: true)
            .build()

        try await client.login(
            username: username,
            password: password,
            initialDeviceName: "Neb macOS",
            deviceId: nil
        )

        self.client = client
        try persistSession(from: client)
        setState(.loggedIn(userID: try client.userId()))
    }

    public func restoreSession() async throws -> Bool {
        let sessionFile = sessionDirectory.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: sessionFile.path) else { return false }

        let sessionData = try Data(contentsOf: sessionFile)
        guard let dict = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any] else { return false }

        guard
            let accessToken = dict["accessToken"] as? String,
            let userId = dict["userId"] as? String,
            let deviceId = dict["deviceId"] as? String,
            let homeserverUrl = dict["homeserverUrl"] as? String,
            let slidingSyncVersionRaw = dict["slidingSyncVersion"] as? String
        else { return false }

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

        let client = try await ClientBuilder()
            .sessionPaths(dataPath: dataPath, cachePath: cachePath)
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .build()

        try await client.restoreSession(session: session)
        self.client = client
        setState(.loggedIn(userID: try client.userId()))
        return true
    }

    public func logout() async throws {
        try await client?.logout()
        client = nil
        let sessionFile = sessionDirectory.appendingPathComponent("session.json")
        try? FileManager.default.removeItem(at: sessionFile)
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
