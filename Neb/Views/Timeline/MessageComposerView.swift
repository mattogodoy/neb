import SwiftUI
import NebCore

struct MessageComposerView: View {
    @Bindable var viewModel: TimelineViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Type a message...", text: $viewModel.composerText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    send()
                }

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(12)
        .onAppear { isFocused = true }
    }

    private func send() {
        let text = viewModel.composerText
        viewModel.composerText = ""
        Task {
            await viewModel.sendMessage(text)
        }
    }
}
