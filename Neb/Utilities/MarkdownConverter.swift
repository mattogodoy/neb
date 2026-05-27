import AppKit
import Foundation

enum MarkdownConverter {
    /// Converts an NSAttributedString to markdown.
    static func convert(_ attributedString: NSAttributedString) -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            let text = (attributedString.string as NSString).substring(with: range)
            guard !text.isEmpty else { return }

            // Check for block-level types
            if let blockType = attrs[.init("NebBlockType")] as? String {
                switch blockType {
                case "codeBlock":
                    result += "```\n\(text)\n```"
                    return
                case "quote":
                    let lines = text.components(separatedBy: "\n")
                    result += lines.map { "> \($0)" }.joined(separator: "\n")
                    return
                case "bulletList":
                    let lines = text.components(separatedBy: "\n")
                    result += lines.map { "- \($0)" }.joined(separator: "\n")
                    return
                case "numberedList":
                    let lines = text.components(separatedBy: "\n")
                    result += lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                    return
                default:
                    break
                }
            }

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
