import Foundation
import Testing
@testable import NebCore

private let testUserID = "@test:example.com"
private let testService = "com.neb.app.tests"

private func makeSession() -> NebSession {
    NebSession(
        accessToken: "token_abc123",
        userId: testUserID,
        deviceId: "DEVICE01",
        homeserverUrl: "https://matrix.example.com",
        slidingSyncVersion: "native",
        refreshToken: "refresh_xyz",
        oauthData: nil
    )
}

@Test func saveAndLoadSession() throws {
    let controller = KeychainController(service: testService)
    defer { controller.deleteAll(for: testUserID) }

    let session = makeSession()
    try controller.saveSession(session, for: testUserID)

    let loaded = controller.loadSession(for: testUserID)
    #expect(loaded == session)
}

@Test func saveAndLoadPassphrase() throws {
    let controller = KeychainController(service: testService)
    defer { controller.deleteAll(for: testUserID) }

    try controller.savePassphrase("my-secret-passphrase", for: testUserID)

    let loaded = controller.loadPassphrase(for: testUserID)
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
    let controller = KeychainController(service: testService)

    let session = makeSession()
    try controller.saveSession(session, for: testUserID)
    try controller.savePassphrase("passphrase", for: testUserID)

    controller.deleteAll(for: testUserID)

    #expect(controller.loadSession(for: testUserID) == nil)
    #expect(controller.loadPassphrase(for: testUserID) == nil)
}

@Test func overwriteSession() throws {
    let controller = KeychainController(service: testService)
    defer { controller.deleteAll(for: testUserID) }

    let session1 = makeSession()
    try controller.saveSession(session1, for: testUserID)

    let session2 = NebSession(
        accessToken: "new_token",
        userId: testUserID,
        deviceId: "DEVICE02",
        homeserverUrl: "https://other.example.com",
        slidingSyncVersion: "native"
    )
    try controller.saveSession(session2, for: testUserID)

    let loaded = controller.loadSession(for: testUserID)
    #expect(loaded?.accessToken == "new_token")
    #expect(loaded?.deviceId == "DEVICE02")
}

@Test func separateUsersDoNotInterfere() throws {
    let controller = KeychainController(service: testService)
    let user1 = "@alice:example.com"
    let user2 = "@bob:example.com"
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
