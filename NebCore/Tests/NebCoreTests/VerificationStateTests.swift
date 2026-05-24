import Testing
@testable import NebCore

@Test func terminalStatesAreTerminal() {
    #expect(VerificationState.confirmed.isTerminal)
    #expect(VerificationState.failed("reason").isTerminal)
    #expect(VerificationState.timedOut.isTerminal)
    #expect(VerificationState.cancelled.isTerminal)
}

@Test func nonTerminalStatesAreNotTerminal() {
    #expect(!VerificationState.idle.isTerminal)
    #expect(!VerificationState.requested.isTerminal)
    #expect(!VerificationState.waitingForAcceptance.isTerminal)
    #expect(!VerificationState.showingEmoji([]).isTerminal)
}

@Test func userActionMessages() {
    #expect(VerificationState.idle.userAction == nil)
    #expect(VerificationState.confirmed.userAction != nil)
    #expect(VerificationState.failed("network").userAction!.contains("network"))
    #expect(VerificationState.showingEmoji([]).userAction!.contains("Compare"))
}
