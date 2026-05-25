import Foundation
import Testing
import AppKit
@testable import NebCore

private func styled(_ text: String, traits: NSFontDescriptor.SymbolicTraits = [], attributes: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
    var font = NSFont.systemFont(ofSize: 13)
    if !traits.isEmpty {
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        font = NSFont(descriptor: descriptor, size: 13) ?? font
    }
    var attrs: [NSAttributedString.Key: Any] = [.font: font]
    attrs.merge(attributes) { _, new in new }
    return NSAttributedString(string: text, attributes: attrs)
}

@Test func convertsPlainText() {
    let input = NSAttributedString(string: "hello world")
    let result = MarkdownConverter.convert(input)
    #expect(result == "hello world")
}

@Test func convertsBoldText() {
    let input = styled("bold", traits: .bold)
    let result = MarkdownConverter.convert(input)
    #expect(result == "**bold**")
}

@Test func convertsItalicText() {
    let input = styled("italic", traits: .italic)
    let result = MarkdownConverter.convert(input)
    #expect(result == "*italic*")
}

@Test func convertsBoldItalicText() {
    let input = styled("both", traits: [.bold, .italic])
    let result = MarkdownConverter.convert(input)
    #expect(result == "***both***")
}

@Test func convertsUnderlineText() {
    let input = styled("underline", attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
    let result = MarkdownConverter.convert(input)
    #expect(result == "__underline__")
}

@Test func convertsStrikethroughText() {
    let input = styled("deleted", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
    let result = MarkdownConverter.convert(input)
    #expect(result == "~~deleted~~")
}

@Test func convertsInlineCode() {
    let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let input = NSAttributedString(string: "code", attributes: [.font: monoFont])
    let result = MarkdownConverter.convert(input)
    #expect(result == "`code`")
}

@Test func convertsMixedFormattingInline() {
    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "hello "))
    result.append(styled("bold", traits: .bold))
    result.append(NSAttributedString(string: " world"))
    let markdown = MarkdownConverter.convert(result)
    #expect(markdown == "hello **bold** world")
}

@Test func convertsCodeBlock() {
    let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let input = NSAttributedString(string: "let x = 1\nlet y = 2", attributes: [
        .font: monoFont,
        .init("NebBlockType"): "codeBlock"
    ])
    let result = MarkdownConverter.convert(input)
    #expect(result == "```\nlet x = 1\nlet y = 2\n```")
}

@Test func convertsQuote() {
    let input = NSAttributedString(string: "wise words", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .init("NebBlockType"): "quote"
    ])
    let result = MarkdownConverter.convert(input)
    #expect(result == "> wise words")
}

@Test func convertsBulletedList() {
    let input = NSAttributedString(string: "item one\nitem two", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .init("NebBlockType"): "bulletList"
    ])
    let result = MarkdownConverter.convert(input)
    #expect(result == "- item one\n- item two")
}

@Test func convertsNumberedList() {
    let input = NSAttributedString(string: "first\nsecond", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .init("NebBlockType"): "numberedList"
    ])
    let result = MarkdownConverter.convert(input)
    #expect(result == "1. first\n2. second")
}

@Test func convertsEmptyString() {
    let input = NSAttributedString(string: "")
    let result = MarkdownConverter.convert(input)
    #expect(result == "")
}

@Test func preservesNewlines() {
    let input = NSAttributedString(string: "line one\nline two")
    let result = MarkdownConverter.convert(input)
    #expect(result == "line one\nline two")
}

@Test func convertsMultipleInlineStyles() {
    let result = NSMutableAttributedString()
    result.append(styled("bold", traits: .bold))
    result.append(NSAttributedString(string: " and "))
    result.append(styled("italic", traits: .italic))
    let markdown = MarkdownConverter.convert(result)
    #expect(markdown == "**bold** and *italic*")
}

@Test func underlineAndBoldCombined() {
    let font = NSFont.boldSystemFont(ofSize: 13)
    let input = NSAttributedString(string: "both", attributes: [
        .font: font,
        .underlineStyle: NSUnderlineStyle.single.rawValue
    ])
    let result = MarkdownConverter.convert(input)
    #expect(result == "**__both__**")
}

@Test func codeBlockPreservesMultipleLines() {
    let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let input = NSAttributedString(string: "func hello() {\n    print(\"hi\")\n}", attributes: [
        .font: monoFont,
        .init("NebBlockType"): "codeBlock"
    ])
    let result = MarkdownConverter.convert(input)
    #expect(result.hasPrefix("```\n"))
    #expect(result.hasSuffix("\n```"))
    #expect(result.contains("func hello()"))
}

@Test func quoteWithMultipleLines() {
    let input = NSAttributedString(string: "line one\nline two", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .init("NebBlockType"): "quote"
    ])
    let result = MarkdownConverter.convert(input)
    #expect(result == "> line one\n> line two")
}
