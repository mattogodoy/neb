import Foundation
import MatrixRustSDK
import os

private let logger = Logger(subsystem: "com.neb.app", category: "Devices")

public final class Devices: DevicesProtocol, @unchecked Sendable {
    private let clientProvider: () -> Client?
    private var verificationStateHandle: TaskHandle?
    private var verificationStateListener: DeviceVerificationStateListenerImpl?

    public init(clientProvider: @escaping () -> Client?) {
        self.clientProvider = clientProvider
    }

    // MARK: - Current device

    public var currentDeviceID: String? {
        get async { try? clientProvider()?.deviceId() }
    }

    public func verificationStatusStream() -> AsyncStream<DeviceVerificationStatus> {
        AsyncStream { continuation in
            guard let client = clientProvider() else {
                continuation.yield(.unknown)
                return
            }
            let encryption = client.encryption()
            let initial = encryption.verificationState()
            continuation.yield(Self.mapVerificationState(initial))

            let listener = DeviceVerificationStateListenerImpl { state in
                continuation.yield(Self.mapVerificationState(state))
            }
            self.verificationStateHandle = encryption.verificationStateListener(listener: listener)
            self.verificationStateListener = listener
        }
    }

    // MARK: - Device state

    public func isLastDevice() async throws -> Bool {
        guard let client = clientProvider() else { return true }
        return try await client.encryption().isLastDevice()
    }

    public func hasOtherDevicesToVerify() async throws -> Bool {
        guard let client = clientProvider() else { return false }
        return try await client.encryption().hasDevicesToVerifyAgainst()
    }

    // MARK: - Device management URLs

    public func devicesListURL() async -> URL? {
        guard let client = clientProvider() else { return nil }
        guard let urlString = try? await client.accountUrl(action: .devicesList) else { return nil }
        return URL(string: urlString)
    }

    public func deviceViewURL(deviceID: String) async -> URL? {
        guard let client = clientProvider() else { return nil }
        guard let urlString = try? await client.accountUrl(action: .deviceView(deviceId: deviceID)) else { return nil }
        return URL(string: urlString)
    }

    public func deviceDeleteURL(deviceID: String) async -> URL? {
        guard let client = clientProvider() else { return nil }
        guard let urlString = try? await client.accountUrl(action: .deviceDelete(deviceId: deviceID)) else { return nil }
        return URL(string: urlString)
    }

    // MARK: - Private

    private static func mapVerificationState(_ state: MatrixRustSDK.VerificationState) -> DeviceVerificationStatus {
        switch state {
        case .verified: return .verified
        case .unverified: return .unverified
        case .unknown: return .unknown
        }
    }
}

private final class DeviceVerificationStateListenerImpl: MatrixRustSDK.VerificationStateListener, @unchecked Sendable {
    private let handler: (MatrixRustSDK.VerificationState) -> Void

    init(handler: @escaping (MatrixRustSDK.VerificationState) -> Void) {
        self.handler = handler
    }

    func onUpdate(status: MatrixRustSDK.VerificationState) {
        handler(status)
    }
}
