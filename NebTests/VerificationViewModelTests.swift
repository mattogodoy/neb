import Foundation
import Testing
@testable import Neb
import NebCore

@Test func verificationInitialStateIsIdle() async {
    let crypto = MockCryptoService()
    let vm = await VerificationViewModel(cryptoService: crypto)
    let state = await vm.state
    #expect(state == .idle)
}

@Test func startDeviceVerification() async throws {
    let crypto = MockCryptoService()
    let vm = await VerificationViewModel(cryptoService: crypto)

    await vm.startDeviceVerification()

    try await Task.sleep(for: .milliseconds(50))
    let state = await vm.state
    #expect(state == .waitingForAcceptance)
}

@Test func acceptShowsEmoji() async throws {
    let crypto = MockCryptoService()
    let vm = await VerificationViewModel(cryptoService: crypto)

    await vm.startDeviceVerification()
    try await Task.sleep(for: .milliseconds(50))

    await vm.acceptVerification()
    try await Task.sleep(for: .milliseconds(50))

    let state = await vm.state
    if case .showingEmoji(let emoji) = state {
        #expect(emoji.count == 7)
        #expect(emoji.first?.symbol == "🐶")
    } else {
        Issue.record("Expected showingEmoji state, got \(state)")
    }
}

@Test func confirmEmojiCompletes() async throws {
    let crypto = MockCryptoService()
    let vm = await VerificationViewModel(cryptoService: crypto)

    await vm.startDeviceVerification()
    try await Task.sleep(for: .milliseconds(50))
    await vm.acceptVerification()
    try await Task.sleep(for: .milliseconds(50))
    await vm.confirmEmoji()
    try await Task.sleep(for: .milliseconds(50))

    let state = await vm.state
    #expect(state == .confirmed)
}

@Test func declineEmojiFails() async throws {
    let crypto = MockCryptoService()
    let vm = await VerificationViewModel(cryptoService: crypto)

    await vm.startDeviceVerification()
    try await Task.sleep(for: .milliseconds(50))
    await vm.acceptVerification()
    try await Task.sleep(for: .milliseconds(50))
    await vm.declineEmoji()
    try await Task.sleep(for: .milliseconds(50))

    let state = await vm.state
    if case .failed = state {
        // expected
    } else {
        Issue.record("Expected failed state, got \(state)")
    }
}

@Test func cancelVerification() async throws {
    let crypto = MockCryptoService()
    let vm = await VerificationViewModel(cryptoService: crypto)

    await vm.startDeviceVerification()
    try await Task.sleep(for: .milliseconds(50))
    await vm.cancelVerification()
    try await Task.sleep(for: .milliseconds(50))

    let state = await vm.state
    #expect(state == .cancelled)
}

@Test func startUserVerification() async throws {
    let crypto = MockCryptoService()
    let vm = await VerificationViewModel(cryptoService: crypto)

    await vm.startUserVerification(userID: "@alice:example.com")

    try await Task.sleep(for: .milliseconds(50))
    let state = await vm.state
    #expect(state == .waitingForAcceptance)
}
