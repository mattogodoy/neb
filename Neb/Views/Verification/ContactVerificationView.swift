import SwiftUI
import NebCore

struct ContactVerificationView: View {
    @Bindable var viewModel: VerificationViewModel
    let contactName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Verify \(contactName)")
                .font(.title2)
                .fontWeight(.semibold)

            Group {
                switch viewModel.state {
                case .idle:
                    Button("Start Verification") {
                        Task { await viewModel.startUserVerification(userID: contactName) }
                    }
                    .buttonStyle(.borderedProminent)

                case .waitingForAcceptance:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Waiting for \(contactName) to accept...")
                            .foregroundStyle(.secondary)
                        Button("Cancel") {
                            Task { await viewModel.cancelVerification() }
                        }
                    }

                case .requested:
                    VStack(spacing: 12) {
                        Text("\(contactName) wants to verify with you")
                        Button("Accept") {
                            Task { await viewModel.acceptVerification() }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                case .showingEmoji(let emoji):
                    VStack(spacing: 16) {
                        Text("Compare these emoji with \(contactName)'s device:")
                            .font(.callout)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                            ForEach(Array(emoji.enumerated()), id: \.offset) { _, item in
                                VStack(spacing: 4) {
                                    Text(item.symbol).font(.system(size: 32))
                                    Text(item.description).font(.caption2).foregroundStyle(.secondary)
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

                case .confirmed:
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("\(contactName) is verified!")
                            .font(.headline)
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }

                case .failed(let reason):
                    VStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                        Text(reason)
                        Button("Try Again") { viewModel.reset() }
                            .buttonStyle(.borderedProminent)
                    }

                case .timedOut:
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        Text("Verification timed out.")
                        Button("Try Again") { viewModel.reset() }
                            .buttonStyle(.borderedProminent)
                    }

                case .cancelled:
                    VStack(spacing: 12) {
                        Text("Verification was cancelled.")
                        Button("Try Again") { viewModel.reset() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(32)
        .frame(minWidth: 400, minHeight: 300)
    }
}
