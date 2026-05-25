import Foundation
import Testing
import AppKit
@testable import NebCore

@Test func togglesBoldOn() {
    let storage = NSTextStorage(string: "hello", attributes: [.font: NSFont.systemFont(ofSize: 13)])
    let range = NSRange(location: 0, length: 5)
    AttributedStringFormatter.toggleTrait(.bold, in: storage, range: range)
    let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
}

@Test func togglesBoldOff() {
    let storage = NSTextStorage(string: "hello", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
    let range = NSRange(location: 0, length: 5)
    AttributedStringFormatter.toggleTrait(.bold, in: storage, range: range)
    let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == false)
}

@Test func togglesItalicOn() {
    let storage = NSTextStorage(string: "hello", attributes: [.font: NSFont.systemFont(ofSize: 13)])
    let range = NSRange(location: 0, length: 5)
    AttributedStringFormatter.toggleTrait(.italic, in: storage, range: range)
    let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
}

@Test func togglesUnderlineOn() {
    let storage = NSTextStorage(string: "hello", attributes: [.font: NSFont.systemFont(ofSize: 13)])
    let range = NSRange(location: 0, length: 5)
    AttributedStringFormatter.toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, in: storage, range: range)
    let underline = storage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
    #expect(underline == NSUnderlineStyle.single.rawValue)
}

@Test func togglesUnderlineOff() {
    let storage = NSTextStorage(string: "hello", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .underlineStyle: NSUnderlineStyle.single.rawValue
    ])
    let range = NSRange(location: 0, length: 5)
    AttributedStringFormatter.toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, in: storage, range: range)
    let underline = storage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
    #expect(underline == nil)
}

@Test func togglesStrikethroughOn() {
    let storage = NSTextStorage(string: "hello", attributes: [.font: NSFont.systemFont(ofSize: 13)])
    let range = NSRange(location: 0, length: 5)
    AttributedStringFormatter.toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, in: storage, range: range)
    let strikethrough = storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
    #expect(strikethrough == NSUnderlineStyle.single.rawValue)
}

@Test func appliesInlineCode() {
    let storage = NSTextStorage(string: "code", attributes: [.font: NSFont.systemFont(ofSize: 13)])
    let range = NSRange(location: 0, length: 4)
    AttributedStringFormatter.applyInlineCode(in: storage, range: range)
    let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
}

@Test func appliesBlockType() {
    let storage = NSTextStorage(string: "line one\nline two", attributes: [.font: NSFont.systemFont(ofSize: 13)])
    let range = NSRange(location: 0, length: storage.length)
    AttributedStringFormatter.applyBlockType("quote", in: storage, range: range)
    let blockType = storage.attribute(.init("NebBlockType"), at: 0, effectiveRange: nil) as? String
    #expect(blockType == "quote")
}

@Test func detectsBoldInAttributes() {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13)]
    #expect(AttributedStringFormatter.isBold(in: attrs) == true)
}

@Test func detectsItalicInAttributes() {
    let descriptor = NSFont.systemFont(ofSize: 13).fontDescriptor.withSymbolicTraits(.italic)
    let font = NSFont(descriptor: descriptor, size: 13)!
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    #expect(AttributedStringFormatter.isItalic(in: attrs) == true)
}

@Test func detectsUnderlineInAttributes() {
    let attrs: [NSAttributedString.Key: Any] = [.underlineStyle: NSUnderlineStyle.single.rawValue]
    #expect(AttributedStringFormatter.isUnderline(in: attrs) == true)
}

@Test func detectsStrikethroughInAttributes() {
    let attrs: [NSAttributedString.Key: Any] = [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
    #expect(AttributedStringFormatter.isStrikethrough(in: attrs) == true)
}

@Test func detectsMonospaceInAttributes() {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
    #expect(AttributedStringFormatter.isMonospace(in: attrs) == true)
}

@Test func noFalsePositivesOnPlainText() {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
    #expect(AttributedStringFormatter.isBold(in: attrs) == false)
    #expect(AttributedStringFormatter.isItalic(in: attrs) == false)
    #expect(AttributedStringFormatter.isUnderline(in: attrs) == false)
    #expect(AttributedStringFormatter.isStrikethrough(in: attrs) == false)
    #expect(AttributedStringFormatter.isMonospace(in: attrs) == false)
}
