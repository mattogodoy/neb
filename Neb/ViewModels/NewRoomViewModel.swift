import NebCore
import Foundation

@MainActor
@Observable
public final class NewRoomViewModel {
    public var roomName: String = ""
    public var inviteUserIDs: String = ""
    public var isCreating = false
    public var errorMessage: String?

    public var canCreate: Bool {
        !roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    private let roomService: any RoomsProtocol

    public init(roomService: any RoomsProtocol) {
        self.roomService = roomService
    }

    public func createRoom() async -> String? {
        guard canCreate else { return nil }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        let name = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let invites = parseUserIDs(inviteUserIDs)

        do {
            return try await roomService.createRoom(
                name: name,
                topic: nil,
                isEncrypted: true,
                isDirect: false,
                inviteUserIDs: invites
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func parseUserIDs(_ input: String) -> [String] {
        input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
