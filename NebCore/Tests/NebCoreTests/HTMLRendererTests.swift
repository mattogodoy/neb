import Foundation
import Testing
import AppKit
@testable import NebCore

@Test func returnsNilForNilInput() {
    let result = HTMLRenderer.render(nil)
    #expect(result == nil)
}

@Test func returnsNilForEmptyString() {
    let result = HTMLRenderer.render("")
    #expect(result == nil)
}

@Test func rendersPlainText() {
    let result = HTMLRenderer.render("Hello world")
    #expect(result != nil)
    #expect(String(result!.characters) .trimmingCharacters(in: .whitespacesAndNewlines) == "Hello world")
}

@Test func rendersBoldText() {
    let result = HTMLRenderer.render("<strong>bold</strong>")
    #expect(result != nil)
    let text = String(result!.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "bold")

    // Check that bold attribute is present
    for run in result!.runs {
        if let font = run.appKit.font {
            let traits = font.fontDescriptor.symbolicTraits
            #expect(traits.contains(.bold))
        }
    }
}

@Test func rendersItalicText() {
    let result = HTMLRenderer.render("<em>italic</em>")
    #expect(result != nil)
    let text = String(result!.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "italic")

    for run in result!.runs {
        if let font = run.appKit.font {
            let traits = font.fontDescriptor.symbolicTraits
            #expect(traits.contains(.italic))
        }
    }
}

@Test func rendersStrikethroughText() {
    let result = HTMLRenderer.render("<del>deleted</del>")
    #expect(result != nil)
    let text = String(result!.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "deleted")

    for run in result!.runs {
        if let strikethrough = run.appKit.strikethroughStyle {
            #expect(strikethrough != .init(rawValue: 0))
        }
    }
}

@Test func rendersLink() {
    let result = HTMLRenderer.render("<a href=\"https://example.com\">link</a>")
    #expect(result != nil)
    let text = String(result!.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "link")

    var foundLink = false
    for run in result!.runs {
        if let link = run.link {
            #expect(link.absoluteString.hasPrefix("https://example.com"))
            foundLink = true
        }
    }
    #expect(foundLink)
}

@Test func rendersCodeText() {
    let result = HTMLRenderer.render("<code>let x = 1</code>")
    #expect(result != nil)
    let text = String(result!.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "let x = 1")

    // Code should use monospace font
    for run in result!.runs {
        if let font = run.appKit.font {
            #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        }
    }
}

@Test func rendersNestedBoldItalic() {
    let result = HTMLRenderer.render("<strong><em>bold italic</em></strong>")
    #expect(result != nil)
    let text = String(result!.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "bold italic")

    for run in result!.runs {
        if let font = run.appKit.font {
            let traits = font.fontDescriptor.symbolicTraits
            #expect(traits.contains(.bold))
            #expect(traits.contains(.italic))
        }
    }
}

@Test func preservesTextFromUnknownTags() {
    let result = HTMLRenderer.render("<div><span>content inside divs</span></div>")
    #expect(result != nil)
    let text = String(result!.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "content inside divs")
}

@Test func respectsCustomForegroundColor() {
    let result = HTMLRenderer.render("hello", foregroundColor: .white)
    #expect(result != nil)
    // Should not crash and should return attributed string
    let text = String(result!.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "hello")
}
