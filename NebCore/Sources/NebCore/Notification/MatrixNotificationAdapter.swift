import Foundation
import UserNotifications
import os
#if canImport(AppKit)
import AppKit
#endif

private let logger = Logger(subsystem: "com.neb.app", category: "Notification")

public final class MatrixNotificationAdapter: NotificationProtocol, @unchecked Sendable {
    public init() {}

    public func requestPermission() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        return try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    public func postNotification(title: String, body: String, roomID: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["roomID": roomID]
        content.threadIdentifier = roomID

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("Failed to post notification for room \(roomID): \(error)")
        }
    }

    public func updateBadgeCount(_ count: UInt) async {
        if #available(macOS 13.0, iOS 16.0, *) {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(Int(count))
            } catch {
                logger.error("Failed to set badge count to \(count): \(error)")
            }
        }

        #if canImport(AppKit)
        await MainActor.run {
            NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
        #endif
    }
}
