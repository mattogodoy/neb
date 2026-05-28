import AppKit
import NebCore

@MainActor
final class HTMLRenderCache {
    static let shared = HTMLRenderCache()

    private var cache: [String: AttributedString] = [:]

    func render(_ html: String?, foregroundColor: NSColor = .labelColor) -> AttributedString? {
        guard let html, !html.isEmpty else { return nil }
        let key = "\(html)\0\(foregroundColor.hash)"
        if let cached = cache[key] {
            return cached
        }
        guard let result = HTMLRenderer.render(html, foregroundColor: foregroundColor) else {
            return nil
        }
        cache[key] = result
        return result
    }
}
