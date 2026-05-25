import SwiftUI
import AppKit
import NebCore

struct MessageComposerView: View {
    @Bindable var viewModel: TimelineViewModel
    @State private var emojiQuery: String?
    @State private var emojiResults: [EmojiItem] = []
    @State private var selectedIndex: Int = 0
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var selectionRect: CGRect = .zero
    @State private var selectionAttributes: [NSAttributedString.Key: Any] = [:]
    @State private var editorState = RichTextEditorState()

    var body: some View {
        VStack(spacing: 0) {
            if let _ = emojiQuery, !emojiResults.isEmpty {
                emojiSuggestions
            }

            if viewModel.editingMessage != nil {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Editing")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { viewModel.cancelEditing() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            HStack(alignment: .bottom, spacing: 8) {
                RichTextEditor(
                    plainText: $viewModel.composerText,
                    selectedRange: $selectedRange,
                    selectionRect: $selectionRect,
                    selectionAttributes: $selectionAttributes,
                    editorState: editorState,
                    onSubmit: { attributed in
                        if viewModel.editingMessage != nil {
                            Task { await viewModel.submitEdit() }
                        } else {
                            send(attributed: attributed)
                        }
                    },
                    onTextChanged: { text in
                        updateEmojiSearch(text)
                        if viewModel.editingMessage == nil {
                            viewModel.onComposerChanged(text: text)
                        }
                    }
                )
                .frame(minHeight: 24, maxHeight: 150)
                .popover(isPresented: Binding(
                    get: { selectedRange.length > 0 },
                    set: { if !$0 { selectedRange = NSRange(location: 0, length: 0) } }
                ), arrowEdge: .top) {
                    FormattingToolbarView(
                        selectionAttributes: selectionAttributes,
                        onFormat: { action in
                            editorState.applyFormatting?(action)
                        }
                    )
                }

                Button(action: {
                    if viewModel.editingMessage != nil {
                        Task { await viewModel.submitEdit() }
                    } else {
                        sendPlain()
                    }
                }) {
                    Image(systemName: viewModel.editingMessage != nil ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
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

    private func send(attributed: NSAttributedString) {
        let markdown = MarkdownConverter.convert(attributed)
        viewModel.composerText = ""
        emojiQuery = nil
        emojiResults = []
        Task {
            await viewModel.sendMessage(markdown)
        }
    }

    private func sendPlain() {
        let text = viewModel.composerText
        viewModel.composerText = ""
        emojiQuery = nil
        emojiResults = []
        Task {
            await viewModel.sendMessage(text)
        }
    }
}
