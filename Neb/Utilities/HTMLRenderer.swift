import AppKit
import SwiftUI

enum HTMLRenderer {
    /// Converts an HTML string to an AttributedString styled for message bubbles.
    /// Returns nil if parsing fails or the input is nil.
    static func render(_ html: String?, baseFont: NSFont = .systemFont(ofSize: 13), foregroundColor: NSColor = .labelColor) -> AttributedString? {
        guard let html, !html.isEmpty else { return nil }

        let styledHTML = """
        <style>
        body {
            font-family: -apple-system, system-ui;
            font-size: \(baseFont.pointSize)px;
        }
        code {
            font-family: Menlo, monospace;
            font-size: \(baseFont.pointSize - 1)px;
            background-color: rgba(128, 128, 128, 0.15);
            padding: 1px 4px;
            border-radius: 3px;
        }
        pre {
            font-family: Menlo, monospace;
            font-size: \(baseFont.pointSize - 1)px;
            background-color: rgba(128, 128, 128, 0.15);
            padding: 8px;
            border-radius: 6px;
            overflow-x: auto;
        }
        blockquote {
            border-left: 3px solid rgba(128, 128, 128, 0.4);
            padding-left: 8px;
            margin-left: 0;
            color: rgba(128, 128, 128, 0.8);
        }
        a {
            color: #007AFF;
        }
        </style>
        \(html)
        """

        guard let data = styledHTML.data(using: .utf8),
              let nsAttr = NSAttributedString(
                html: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return nil
        }

        // Convert to AttributedString for SwiftUI
        var result = AttributedString(nsAttr)

        // Post-process: override the foreground color
        // (HTML parsing may set it to black, which won't work in dark mode)
        let swiftUIColor = Color(nsColor: foregroundColor)
        result.foregroundColor = swiftUIColor

        // Re-apply link colors
        for run in result.runs {
            if run.link != nil {
                result[run.range].foregroundColor = Color.accentColor
            }
        }

        return result
    }
}
