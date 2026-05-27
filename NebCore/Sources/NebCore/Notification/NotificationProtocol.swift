import Foundation

public protocol NotificationProtocol: Sendable {
    func requestPermission() async throws -> Bool
    func postNotification(title: String, body: String, roomID: String) async
    func updateBadgeCount(_ count: UInt) async
}
