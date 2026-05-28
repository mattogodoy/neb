import Foundation

public enum DeviceVerificationStatus: Equatable, Sendable {
    case unknown
    case verified
    case unverified
}

public protocol DevicesProtocol: Sendable {
    // Current device
    var currentDeviceID: String? { get async }
    func verificationStatusStream() -> AsyncStream<DeviceVerificationStatus>

    // Device state
    func isLastDevice() async throws -> Bool
    func hasOtherDevicesToVerify() async throws -> Bool

    // Device management (web URLs)
    func devicesListURL() async -> URL?
    func deviceViewURL(deviceID: String) async -> URL?
    func deviceDeleteURL(deviceID: String) async -> URL?
}
