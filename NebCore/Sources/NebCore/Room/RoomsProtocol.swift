import Foundation

public protocol RoomsProtocol: Sendable {
    func createRoom(name: String?, topic: String?, isEncrypted: Bool, isDirect: Bool, inviteUserIDs: [String]) async throws -> String
    func createDM(userID: String) async throws -> String
    func joinRoom(roomIDOrAlias: String) async throws
    func leaveRoom(roomID: String) async throws
    func setRoomName(roomID: String, name: String) async throws
    func setRoomTopic(roomID: String, topic: String) async throws
    func setRoomAvatar(roomID: String, data: Data, mimeType: String) async throws
    func roomInfo(roomID: String) async throws -> NebRoom
}
