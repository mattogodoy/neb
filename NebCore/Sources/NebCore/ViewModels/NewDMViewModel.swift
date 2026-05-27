import Foundation

@MainActor
@Observable
public final class NewDMViewModel {
    public var userID: String = ""
    public var isCreating = false
    public var errorMessage: String?

    public var canCreate: Bool {
        isValidMatrixID(userID) && !isCreating
    }

    private let roomService: any RoomProtocol

    public init(roomService: any RoomProtocol) {
        self.roomService = roomService
    }

    public func setUserID(_ value: String) {
        userID = value
        errorMessage = nil
    }

    public func createDM() async -> String? {
        guard canCreate else { return nil }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            return try await roomService.createDM(userID: userID)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func isValidMatrixID(_ id: String) -> Bool {
        let pattern = #"^@[a-zA-Z0-9._=/\-]+:[a-zA-Z0-9.\-]+(:[0-9]+)?$"#
        return id.range(of: pattern, options: .regularExpression) != nil
    }
}
