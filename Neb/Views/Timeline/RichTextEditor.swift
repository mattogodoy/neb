import AppKit
import SwiftUI
import NebCore

// NOTE: iOS future — replace NSViewRepresentable/NSTextView with
// UIViewRepresentable/UITextView. Same public interface, same bindings.
// Use #if os(macOS) / #else to branch when adding the iOS target.

enum FormattingAction {
    case bold, italic, underline, strikethrough, inlineCode
    case codeBlock, bulletList, numberedList, quote
}

class RichTextEditorState: ObservableObject {
    var applyFormatting: ((FormattingAction) -> Void)?
}

class AutoSizingScrollView: NSScrollView {
    private let maxContentHeight: CGFloat = 150
    private let minContentHeight: CGFloat = 24

    override var intrinsicContentSize: NSSize {
        guard let textView = documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: minContentHeight)
        }
        layoutManager.ensureLayout(for: textContainer)
        let textHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
        let clampedHeight = min(max(textHeight, minContentHeight), maxContentHeight)
        return NSSize(width: NSView.noIntrinsicMetric, height: clampedHeight)
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var plainText: String
    @Binding var selectedRange: NSRange
    @Binding var selectionRect: CGRect
    @Binding var selectionAttributes: [NSAttributedString.Key: Any]
    var editorState: RichTextEditorState?
    var onSubmit: (NSAttributedString) -> Void
    var onTextChanged: (String) -> Void

    func makeNSView(context: Context) -> AutoSizingScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 4)

        // Single-line height by default, grows with content
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = AutoSizingScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        context.coordinator.textView = textView

        // Wire formatting callback
        let coordinator = context.coordinator
        editorState?.applyFormatting = { action in
            coordinator.applyFormatting(action)
        }

        // Focus on appear
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: AutoSizingScrollView, context: Context) {
        // Sync from SwiftUI to NSTextView only when cleared (after send)
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if plainText.isEmpty && textView.string != "" {
            textView.string = ""
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let text = textView.string
            parent.plainText = text
            parent.onTextChanged(text)
            // Resize scroll view to fit content
            textView.enclosingScrollView?.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let range = textView.selectedRange()

            // Defer binding updates to avoid modifying state during view update
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.selectedRange = range

                // Get selection rect for toolbar positioning
                if range.length > 0, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    let viewRect = textView.convert(rect, to: nil)
                    self.parent.selectionRect = viewRect
                } else {
                    self.parent.selectionRect = .zero
                }

                // Get attributes at selection
                if range.length > 0, let storage = textView.textStorage, range.location < storage.length {
                    self.parent.selectionAttributes = storage.attributes(at: range.location, effectiveRange: nil)
                } else {
                    self.parent.selectionAttributes = [:]
                }
            }
        }

        func applyFormatting(_ action: FormattingAction) {
            guard let textView else { return }
            let storage = textView.textStorage!
            let range = textView.selectedRange()

            guard range.length > 0 || isBlockAction(action) else { return }

            storage.beginEditing()

            switch action {
            case .bold:
                AttributedStringFormatter.toggleTrait(.bold, in: storage, range: range)
            case .italic:
                AttributedStringFormatter.toggleTrait(.italic, in: storage, range: range)
            case .underline:
                AttributedStringFormatter.toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, in: storage, range: range)
            case .strikethrough:
                AttributedStringFormatter.toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, in: storage, range: range)
            case .inlineCode:
                AttributedStringFormatter.applyInlineCode(in: storage, range: range)
            case .codeBlock:
                AttributedStringFormatter.applyBlockType("codeBlock", in: storage, range: range)
            case .bulletList:
                AttributedStringFormatter.applyBlockType("bulletList", in: storage, range: range)
            case .numberedList:
                AttributedStringFormatter.applyBlockType("numberedList", in: storage, range: range)
            case .quote:
                AttributedStringFormatter.applyBlockType("quote", in: storage, range: range)
            }

            storage.endEditing()
            textView.didChangeText()
        }

        private func isBlockAction(_ action: FormattingAction) -> Bool {
            switch action {
            case .codeBlock, .bulletList, .numberedList, .quote: return true
            default: return false
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Shift+Enter: insert newline
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                // Enter: send
                let attributed = textView.attributedString()
                let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return true }
                parent.onSubmit(NSAttributedString(attributedString: attributed))
                return true
            }
            return false
        }
    }
}
