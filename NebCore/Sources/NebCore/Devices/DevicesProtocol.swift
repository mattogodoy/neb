import Foundation

public enum DeviceVerificationStatus: Equatable, Sendable {
    case unknown
    case verified
    case unverified
}

public protocol DevicesProtocol: Sendable {
    func currentDeviceID() async -> String?
    func deviceVerificationStatusStream() -> AsyncStream<DeviceVerificationStatus>
}
