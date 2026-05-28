import SwiftUI
import NebCore

struct ContactVerificationView: View {
    @Bindable var viewModel: VerificationViewModel
    let userID: String
    let displayName: String
    var securityService: (any SecurityProtocol)?
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirming = false
    @State private var isAlreadyVerified = false
    @State private var isCheckingStatus = true

    var body: some View {
        VStack(spacing: 20) {
            Group {
                if isCheckingStatus {
                    ProgressView()
                } else {
                    switch viewModel.state {
                    case .idle:
                        idleView
                    case .waitingForAcceptance:
                        waitingView
                    case .requested:
                        requestedView
                    case .showingEmoji(let emoji):
                        emojiView(emoji)
                    case .confirmed:
                        confirmedView
                    case .failed(let reason):
                        failedView(reason)
                    case .timedOut:
                        timedOutView
                    case .cancelled:
                        cancelledView
                    }
                }
            }
        }
        .padding(32)
        .frame(minWidth: 440, minHeight: 300)
        .task {
            isAlreadyVerified = await securityService?.isUserVerified(userID: userID) ?? false
            isCheckingStatus = false
        }
    }

    private func close() {
        Task { await viewModel.cancelVerification() }
        dismiss()
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            if isAlreadyVerified {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("\(displayName) is verified")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("You've confirmed this user's identity. Your conversations are secure.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                Text(userID)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospaced()

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            } else {
                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Verify \(displayName)")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Verifying confirms that you're really talking to \(displayName) and not an impersonator. You'll compare emoji on both sides.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                Text(userID)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospaced()

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                Button("Start Verification") {
                    Task { await viewModel.startUserVerification(userID: userID) }
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var waitingView: some View {
        VStack(spacing: 16) {
            Text("Waiting for \(displayName)")
                .font(.title3)
                .fontWeight(.semibold)
            Text("\(displayName) needs to accept the verification request on their device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            ProgressView()
            Button("Cancel") { close() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var requestedView: some View {
        VStack(spacing: 16) {
            Text("Verification request")
                .font(.title3)
                .fontWeight(.semibold)
            Text("\(displayName) wants to verify with you.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Accept") {
                Task { await viewModel.acceptVerification() }
            }
            .buttonStyle(.borderedProminent)
            Button("Decline") { close() }
        }
    }

    private func emojiView(_ emoji: [VerificationEmoji]) -> some View {
        VStack(spacing: 24) {
            Text("Compare emoji")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Confirm the emoji below match those shown on \(displayName)'s device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            VStack(spacing: 20) {
                let topRow = Array(emoji.prefix(4))
                let bottomRow = Array(emoji.dropFirst(4))

                HStack(spacing: 24) {
                    ForEach(Array(topRow.enumerated()), id: \.offset) { _, item in
                        emojiCell(item)
                    }
                }

                HStack(spacing: 24) {
                    ForEach(Array(bottomRow.enumerated()), id: \.offset) { _, item in
                        emojiCell(item)
                    }
                }
            }

            if isConfirming {
                ProgressView()
                Text("Confirming...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    Button("They Match") {
                        isConfirming = true
                        Task { await viewModel.confirmEmoji() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("They Don't Match") {
                        Task { await viewModel.declineEmoji() }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func emojiCell(_ item: VerificationEmoji) -> some View {
        VStack(spacing: 6) {
            Text(item.symbol)
                .font(.system(size: 40))
            Text(item.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 80)
    }

    private var confirmedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("\(displayName) is verified")
                .font(.title3)
                .fontWeight(.semibold)
            Text("You can now be confident that your messages with \(displayName) are secure.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func failedView(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Verification failed")
                .font(.title3)
                .fontWeight(.semibold)
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Try Again") { viewModel.reset() }
                .buttonStyle(.borderedProminent)
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var timedOutView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Verification timed out")
                .font(.title3)
                .fontWeight(.semibold)
            Text("\(displayName) didn't respond in time.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Try Again") { viewModel.reset() }
                .buttonStyle(.borderedProminent)
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var cancelledView: some View {
        VStack(spacing: 12) {
            Text("Verification was cancelled.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
        }
    }
}
