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

    public func currentDeviceID() async -> String? {
        try? clientProvider()?.deviceId()
    }

    public func deviceVerificationStatusStream() -> AsyncStream<DeviceVerificationStatus> {
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
