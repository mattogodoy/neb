import AppKit
import Foundation

public enum MarkdownConverter {
    /// Converts an NSAttributedString to markdown.
    public static func convert(_ attributedString: NSAttributedString) -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            let text = (attributedString.string as NSString).substring(with: range)
            guard !text.isEmpty else { return }

            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isMonospace = traits.contains(.monoSpace)
            let isBold = traits.contains(.bold)
            let isItalic = traits.contains(.italic)
            let hasUnderline = (attrs[.underlineStyle] as? Int).map { $0 != 0 } ?? false
            let hasStrikethrough = (attrs[.strikethroughStyle] as? Int).map { $0 != 0 } ?? false

            var chunk = text

            if isMonospace {
                chunk = "`\(chunk)`"
            } else {
                if hasStrikethrough {
                    chunk = "~~\(chunk)~~"
                }
                if hasUnderline {
                    chunk = "__\(chunk)__"
                }
                if isBold && isItalic {
                    chunk = "***\(chunk)***"
                } else if isBold {
                    chunk = "**\(chunk)**"
                } else if isItalic {
                    chunk = "*\(chunk)*"
                }
            }

            result += chunk
        }

        return result
    }
}
