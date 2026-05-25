import SwiftUI
import NebCore

struct MessageComposerView: View {
    @Bindable var viewModel: TimelineViewModel
    @FocusState private var isFocused: Bool
    @State private var emojiQuery: String?
    @State private var emojiResults: [EmojiItem] = []
    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            if let query = emojiQuery, !emojiResults.isEmpty {
                emojiSuggestions
            }

            HStack(spacing: 8) {
                TextField("Type a message...", text: $viewModel.composerText)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        if emojiQuery != nil && !emojiResults.isEmpty {
                            insertEmoji(emojiResults[selectedIndex])
                        } else {
                            send()
                        }
                    }
                    .onChange(of: viewModel.composerText) { _, newValue in
                        updateEmojiSearch(newValue)
                        viewModel.onComposerChanged(text: newValue)
                    }
                    .onKeyPress(.upArrow) {
                        if emojiQuery != nil && !emojiResults.isEmpty {
                            selectedIndex = max(0, selectedIndex - 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        if emojiQuery != nil && !emojiResults.isEmpty {
                            selectedIndex = min(emojiResults.count - 1, selectedIndex + 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        if emojiQuery != nil {
                            emojiQuery = nil
                            emojiResults = []
                            return .handled
                        }
                        return .ignored
                    }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
        .onAppear { isFocused = true }
    }

    // MARK: - Emoji Suggestions

    private var emojiSuggestions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(emojiResults.prefix(8).enumerated()), id: \.element.id) { index, item in
                        Button(action: { insertEmoji(item) }) {
                            HStack(spacing: 8) {
                                Text(item.emoji)
                                    .font(.system(size: 18))
                                Text(item.keywords.first ?? item.emoji)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(index == selectedIndex ? Color.accentColor.opacity(0.2) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
            }
            .frame(maxHeight: 200)
            .onChange(of: selectedIndex) { _, newIndex in
                proxy.scrollTo(newIndex)
            }
        }
        .background(Color(.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Logic

    private func updateEmojiSearch(_ text: String) {
        guard let colonIndex = text.lastIndex(of: ":") else {
            emojiQuery = nil
            emojiResults = []
            return
        }

        let afterColon = text[text.index(after: colonIndex)...]

        if afterColon.contains(" ") {
            emojiQuery = nil
            emojiResults = []
            return
        }

        let query = String(afterColon)
        if query.isEmpty {
            emojiQuery = ""
            emojiResults = Array(EmojiData.categories.flatMap(\.emojis).prefix(8))
        } else if query.count >= 2 {
            emojiQuery = query
            emojiResults = EmojiData.search(query)
        } else {
            emojiQuery = query
            emojiResults = []
        }
        selectedIndex = 0
    }

    private func insertEmoji(_ item: EmojiItem) {
        if let colonIndex = viewModel.composerText.lastIndex(of: ":") {
            viewModel.composerText = String(viewModel.composerText[..<colonIndex]) + item.emoji
        }
        emojiQuery = nil
        emojiResults = []
    }

    private func send() {
        let text = viewModel.composerText
        viewModel.composerText = ""
        emojiQuery = nil
        emojiResults = []
        Task {
            await viewModel.sendMessage(text)
        }
    }
}
