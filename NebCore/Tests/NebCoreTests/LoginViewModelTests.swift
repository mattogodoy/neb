import Testing
@testable import NebCore

@Test func initialState() async {
    let mock = MockAuthService()
    let vm = await LoginViewModel(authService: mock)
    let state = await vm.authState
    #expect(state == .loggedOut)
    let loading = await vm.isLoading
    #expect(!loading)
}

@Test func loginSuccess() async throws {
    let mock = MockAuthService()
    let vm = await LoginViewModel(authService: mock)

    await vm.setHomeserver("https://matrix.example.com")
    await vm.setUsername("alice")
    await vm.setPassword("secret")
    await vm.login()

    let state = await vm.authState
    #expect(state == .loggedIn(userID: "@alice:https://matrix.example.com"))
}

@Test func loginFailure() async throws {
    let mock = MockAuthService()
    mock.loginResult = .failure(NSError(domain: "test", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"]))
    let vm = await LoginViewModel(authService: mock)

    await vm.setHomeserver("https://matrix.example.com")
    await vm.setUsername("alice")
    await vm.setPassword("wrong")
    await vm.login()

    let error = await vm.errorMessage
    #expect(error != nil)
    #expect(error!.contains("Invalid credentials"))
}

@Test func loginDisabledWithEmptyFields() async {
    let mock = MockAuthService()
    let vm = await LoginViewModel(authService: mock)
    let canLogin = await vm.canLogin
    #expect(!canLogin)

    await vm.setHomeserver("https://matrix.example.com")
    await vm.setUsername("alice")
    let stillCant = await vm.canLogin
    #expect(!stillCant)

    await vm.setPassword("secret")
    let canNow = await vm.canLogin
    #expect(canNow)
}

@Test func restoreSessionSuccess() async throws {
    let mock = MockAuthService()
    mock.restoreResult = true
    let vm = await LoginViewModel(authService: mock)
    let restored = await vm.tryRestoreSession()
    #expect(restored)
}
