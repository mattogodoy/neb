import SwiftUI
import NebCore

struct DeviceVerificationView: View {
    @Bindable var viewModel: VerificationViewModel

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

            if let action = viewModel.state.userAction {
                Text(action)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(width: 400, minHeight: 300)
    }

    private var idleView: some View {
        Button("Verify This Device") {
            Task { await viewModel.startDeviceVerification() }
        }
        .buttonStyle(.borderedProminent)
    }

    private var waitingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Button("Cancel") {
                Task { await viewModel.cancelVerification() }
            }
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
        VStack(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(Array(emoji.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 4) {
                        Text(item.symbol)
                            .font(.system(size: 32))
                        Text(item.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("They Don't Match") {
                    Task { await viewModel.declineEmoji() }
                }

                Button("They Match") {
                    Task { await viewModel.confirmEmoji() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var confirmedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Device Verified")
                .font(.headline)
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
            Button("Try Again") { viewModel.reset() }
                .buttonStyle(.borderedProminent)
        }
    }
}
