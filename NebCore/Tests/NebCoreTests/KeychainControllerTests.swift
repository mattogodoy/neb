import Foundation
import Testing
@testable import NebCore

private let testService = "com.neb.app.tests"

private func makeSession(userId: String = "@test:example.com") -> NebSession {
    NebSession(
        accessToken: "token_abc123",
        userId: userId,
        deviceId: "DEVICE01",
        homeserverUrl: "https://matrix.example.com",
        slidingSyncVersion: "native",
        refreshToken: "refresh_xyz",
        oauthData: nil
    )
}

@Test func saveAndLoadSession() throws {
    let userID = "@save-load-session:example.com"
    let controller = KeychainController(service: testService)
    defer { controller.deleteAll(for: userID) }

    let session = makeSession(userId: userID)
    try controller.saveSession(session, for: userID)

    let loaded = controller.loadSession(for: userID)
    #expect(loaded == session)
}

@Test func saveAndLoadPassphrase() throws {
    let userID = "@save-load-passphrase:example.com"
    let controller = KeychainController(service: testService)
    defer { controller.deleteAll(for: userID) }

    try controller.savePassphrase("my-secret-passphrase", for: userID)

    let loaded = controller.loadPassphrase(for: userID)
    #expect(loaded == "my-secret-passphrase")
}

@Test func loadNonExistentSessionReturnsNil() {
    let controller = KeychainController(service: testService)
    let loaded = controller.loadSession(for: "@nobody:example.com")
    #expect(loaded == nil)
}

@Test func loadNonExistentPassphraseReturnsNil() {
    let controller = KeychainController(service: testService)
    let loaded = controller.loadPassphrase(for: "@nobody:example.com")
    #expect(loaded == nil)
}

@Test func deleteAllClearsBoth() throws {
    let userID = "@delete-all:example.com"
    let controller = KeychainController(service: testService)

    let session = makeSession(userId: userID)
    try controller.saveSession(session, for: userID)
    try controller.savePassphrase("passphrase", for: userID)

    controller.deleteAll(for: userID)

    #expect(controller.loadSession(for: userID) == nil)
    #expect(controller.loadPassphrase(for: userID) == nil)
}

@Test func overwriteSession() throws {
    let userID = "@overwrite:example.com"
    let controller = KeychainController(service: testService)
    defer { controller.deleteAll(for: userID) }

    let session1 = makeSession(userId: userID)
    try controller.saveSession(session1, for: userID)

    let session2 = NebSession(
        accessToken: "new_token",
        userId: userID,
        deviceId: "DEVICE02",
        homeserverUrl: "https://other.example.com",
        slidingSyncVersion: "native"
    )
    try controller.saveSession(session2, for: userID)

    let loaded = controller.loadSession(for: userID)
    #expect(loaded?.accessToken == "new_token")
    #expect(loaded?.deviceId == "DEVICE02")
}

@Test func separateUsersDoNotInterfere() throws {
    let controller = KeychainController(service: testService)
    let user1 = "@separate-alice:example.com"
    let user2 = "@separate-bob:example.com"
    defer {
        controller.deleteAll(for: user1)
        controller.deleteAll(for: user2)
    }

    let session1 = NebSession(accessToken: "alice_token", userId: user1, deviceId: "A1", homeserverUrl: "https://m.io", slidingSyncVersion: "native")
    let session2 = NebSession(accessToken: "bob_token", userId: user2, deviceId: "B1", homeserverUrl: "https://m.io", slidingSyncVersion: "native")

    try controller.saveSession(session1, for: user1)
    try controller.saveSession(session2, for: user2)

    #expect(controller.loadSession(for: user1)?.accessToken == "alice_token")
    #expect(controller.loadSession(for: user2)?.accessToken == "bob_token")

    controller.deleteAll(for: user1)
    #expect(controller.loadSession(for: user1) == nil)
    #expect(controller.loadSession(for: user2)?.accessToken == "bob_token")
}
