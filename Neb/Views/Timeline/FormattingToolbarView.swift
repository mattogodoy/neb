import SwiftUI
import AppKit
import NebCore

struct FormattingToolbarView: View {
    let selectionAttributes: [NSAttributedString.Key: Any]
    let onFormat: (FormattingAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            // Inline styles
            formatButton("Bold", systemImage: "bold", action: .bold, isActive: AttributedStringFormatter.isBold(in: selectionAttributes))
            formatButton("Italic", systemImage: "italic", action: .italic, isActive: AttributedStringFormatter.isItalic(in: selectionAttributes))
            formatButton("Underline", systemImage: "underline", action: .underline, isActive: AttributedStringFormatter.isUnderline(in: selectionAttributes))
            formatButton("Strikethrough", systemImage: "strikethrough", action: .strikethrough, isActive: AttributedStringFormatter.isStrikethrough(in: selectionAttributes))
            formatButton("Inline Code", systemImage: "chevron.left.forwardslash.chevron.right", action: .inlineCode, isActive: AttributedStringFormatter.isMonospace(in: selectionAttributes))

            Divider().frame(height: 16)

            // Block styles
            formatButton("Code Block", systemImage: "doc.text", action: .codeBlock)
            formatButton("Bullet List", systemImage: "list.bullet", action: .bulletList)
            formatButton("Numbered List", systemImage: "list.number", action: .numberedList)
            formatButton("Quote", systemImage: "text.quote", action: .quote)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func formatButton(_ label: String, systemImage: String, action: FormattingAction, isActive: Bool = false) -> some View {
        Button(action: { onFormat(action) }) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
