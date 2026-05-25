import AppKit
import Foundation

public enum AttributedStringFormatter {
    // MARK: - Toggle traits

    public static func toggleTrait(_ trait: NSFontDescriptor.SymbolicTraits, in storage: NSTextStorage, range: NSRange) {
        var hasAll = true
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            guard let font = value as? NSFont else { hasAll = false; return }
            if !font.fontDescriptor.symbolicTraits.contains(trait) { hasAll = false }
        }

        storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
            guard let font = value as? NSFont else { return }
            var newTraits = font.fontDescriptor.symbolicTraits
            if hasAll {
                newTraits.remove(trait)
            } else {
                newTraits.insert(trait)
            }
            let descriptor = font.fontDescriptor.withSymbolicTraits(newTraits)
            let newFont = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
            storage.addAttribute(.font, value: newFont, range: subRange)
        }
    }

    // MARK: - Toggle attributes

    public static func toggleAttribute(_ key: NSAttributedString.Key, value: Any, in storage: NSTextStorage, range: NSRange) {
        var hasAll = true
        storage.enumerateAttribute(key, in: range) { existing, _, _ in
            if existing == nil { hasAll = false }
        }

        if hasAll {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: value, range: range)
        }
    }

    // MARK: - Inline code

    public static func applyInlineCode(in storage: NSTextStorage, range: NSRange) {
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        storage.addAttribute(.font, value: monoFont, range: range)
    }

    // MARK: - Block types

    public static func applyBlockType(_ type: String, in storage: NSTextStorage, range: NSRange) {
        let lineRange = (storage.string as NSString).lineRange(for: range)
        storage.addAttribute(.init("NebBlockType"), value: type, range: lineRange)

        if type == "codeBlock" {
            let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            storage.addAttribute(.font, value: monoFont, range: lineRange)
        }
    }

    // MARK: - State detection

    public static func isBold(in attrs: [NSAttributedString.Key: Any]) -> Bool {
        guard let font = attrs[.font] as? NSFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.bold)
    }

    public static func isItalic(in attrs: [NSAttributedString.Key: Any]) -> Bool {
        guard let font = attrs[.font] as? NSFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.italic)
    }

    public static func isUnderline(in attrs: [NSAttributedString.Key: Any]) -> Bool {
        (attrs[.underlineStyle] as? Int).map { $0 != 0 } ?? false
    }

    public static func isStrikethrough(in attrs: [NSAttributedString.Key: Any]) -> Bool {
        (attrs[.strikethroughStyle] as? Int).map { $0 != 0 } ?? false
    }

    public static func isMonospace(in attrs: [NSAttributedString.Key: Any]) -> Bool {
        guard let font = attrs[.font] as? NSFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.monoSpace)
    }
}
