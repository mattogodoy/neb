import SwiftUI
import NebCore

struct DeviceVerificationView: View {
    @Bindable var viewModel: VerificationViewModel
    var isAlreadyVerified: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Device Verification")
                .font(.title2)
                .fontWeight(.semibold)

            Group {
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

            if case .showingEmoji = viewModel.state {} else {
                if let action = viewModel.state.userAction {
                    Text(action)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(32)
        .frame(minWidth: 400, minHeight: 300)
    }

    private func close() {
        Task { await viewModel.cancelVerification() }
        dismiss()
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            if isAlreadyVerified {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("This device is already verified.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button(isAlreadyVerified ? "Verify Again" : "Verify This Device") {
                Task { await viewModel.startDeviceVerification() }
            }
            .buttonStyle(.borderedProminent)

            Button(isAlreadyVerified ? "Done" : "Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var waitingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Button("Cancel") { close() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var requestedView: some View {
        VStack(spacing: 12) {
            Text("Verification request received")
            Button("Accept") {
                Task { await viewModel.acceptVerification() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func emojiView(_ emoji: [VerificationEmoji]) -> some View {
        VStack(spacing: 24) {
            Text("Confirm the emojis below match those shown on your other device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

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

            HStack(spacing: 12) {
                Button("They Match") {
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
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Device Verified")
                .font(.headline)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func failedView(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text(reason)
                .font(.callout)
            Button("Try Again") { viewModel.reset() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var timedOutView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Button("Try Again") { viewModel.reset() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var cancelledView: some View {
        VStack(spacing: 12) {
            Text("Verification was cancelled.")
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
        }
    }
}
