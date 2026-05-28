import SwiftUI
import NebCore

struct DeviceVerificationView: View {
    @Bindable var viewModel: VerificationViewModel
    var isAlreadyVerified: Bool = false
    var securityService: (any SecurityProtocol)?
    @Environment(\.dismiss) private var dismiss

    @State private var showRecoveryKeyInput = false
    @State private var recoveryKey = ""
    @State private var isRecovering = false
    @State private var recoveryError: String?
    @State private var recoveryComplete = false
    @State private var isConfirming = false

    var body: some View {
        VStack(spacing: 20) {
            Group {
                if showRecoveryKeyInput {
                    recoveryKeyView
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
        .frame(minWidth: 440, minHeight: 320)
    }

    private func close() {
        Task { await viewModel.cancelVerification() }
        dismiss()
    }

    // MARK: - Idle / Method Selection

    private var idleView: some View {
        VStack(spacing: 20) {
            if isAlreadyVerified {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("This device is verified")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Your encrypted messages are accessible. You can re-verify or restore keys from backup if needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            } else {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Verify this device")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Verify to access your encrypted messages. Choose one of the methods below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            VStack(spacing: 10) {
                verificationMethodButton(
                    icon: "laptopcomputer.and.iphone",
                    title: "Verify from another device",
                    subtitle: "Compare emoji with a device that's already verified (e.g. Element X)."
                ) {
                    Task { await viewModel.startDeviceVerification() }
                }

                verificationMethodButton(
                    icon: "key.fill",
                    title: "Enter recovery key",
                    subtitle: "Use your account's recovery key to restore access to encrypted messages."
                ) {
                    showRecoveryKeyInput = true
                }
            }

            Button(isAlreadyVerified ? "Done" : "Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func verificationMethodButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 36)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: 380)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Device Verification Flow

    private var waitingView: some View {
        VStack(spacing: 16) {
            Text("Waiting for another device")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Accept the verification request on your other device to continue.")
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
            Text("Verification request received")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Another device wants to verify this session.")
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
            Text("Confirm the emoji below match those shown on your other device.")
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
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Verification complete")
                .font(.title3)
                .fontWeight(.semibold)
            Text("This device is now verified. Your encrypted messages will be decrypted as keys are received from your other devices.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Recovery Key Flow

    private var recoveryKeyView: some View {
        VStack(spacing: 16) {
            if recoveryComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Keys restored")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Your encryption keys have been restored. Encrypted messages will now be decrypted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            } else if isRecovering {
                Text("Restoring encryption keys")
                    .font(.title3)
                    .fontWeight(.semibold)
                ProgressView()
                    .controlSize(.large)
                Text("Downloading keys from backup. This may take a moment.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "key.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Enter recovery key")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Your recovery key was provided when you first set up encryption. It's usually a long string starting with a capital letter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                TextField("Recovery Key", text: $recoveryKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                    .onSubmit { recover() }

                if let error = recoveryError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack(spacing: 12) {
                    Button("Restore Keys") { recover() }
                        .buttonStyle(.borderedProminent)
                        .disabled(recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Back") {
                        showRecoveryKeyInput = false
                        recoveryError = nil
                        recoveryKey = ""
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private func recover() {
        let key = recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isRecovering = true
        recoveryError = nil
        Task {
            do {
                try await securityService?.recoverKeys(recoveryKey: key)
                recoveryComplete = true
            } catch {
                recoveryError = error.localizedDescription
            }
            isRecovering = false
        }
    }

    // MARK: - Error States

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
            Text("The other device didn't respond in time.")
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
