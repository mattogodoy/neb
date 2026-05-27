import Foundation

public struct NebSession: Codable, Sendable, Equatable {
    public let accessToken: String
    public let userId: String
    public let deviceId: String
    public let homeserverUrl: String
    public let slidingSyncVersion: String
    public var refreshToken: String?
    public var oauthData: String?

    public init(
        accessToken: String,
        userId: String,
        deviceId: String,
        homeserverUrl: String,
        slidingSyncVersion: String,
        refreshToken: String? = nil,
        oauthData: String? = nil
    ) {
        self.accessToken = accessToken
        self.userId = userId
        self.deviceId = deviceId
        self.homeserverUrl = homeserverUrl
        self.slidingSyncVersion = slidingSyncVersion
        self.refreshToken = refreshToken
        self.oauthData = oauthData
    }
}
