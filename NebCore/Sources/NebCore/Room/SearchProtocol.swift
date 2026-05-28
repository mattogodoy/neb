import Foundation

public protocol SearchProtocol: Sendable {
    func search(query: String, roomID: String) async throws -> [SearchResult]
}
