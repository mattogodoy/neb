import Foundation
#if canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

public final class AvatarImageCache: @unchecked Sendable {
    public static let shared = AvatarImageCache()

    private let cache = NSCache<NSString, PlatformImage>()
    private var inflight: [String: Task<PlatformImage?, Never>] = [:]
    private let lock = NSLock()

    private init() {
        cache.countLimit = 200
    }

    public func image(for mxcURL: String, homeserverURL: String) async -> PlatformImage? {
        if let cached = cache.object(forKey: mxcURL as NSString) {
            return cached
        }

        let existingTask: Task<PlatformImage?, Never>? = lock.withLock { inflight[mxcURL] }
        if let existing = existingTask {
            return await existing.value
        }

        let task = Task<PlatformImage?, Never> {
            guard let httpURL = self.thumbnailURL(mxc: mxcURL, homeserver: homeserverURL) else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: httpURL)
                guard let image = PlatformImage(data: data) else { return nil }
                self.cache.setObject(image, forKey: mxcURL as NSString)
                return image
            } catch {
                return nil
            }
        }

        lock.withLock { inflight[mxcURL] = task }

        let result = await task.value

        _ = lock.withLock { inflight.removeValue(forKey: mxcURL) }

        return result
    }

    private func thumbnailURL(mxc: String, homeserver: String) -> URL? {
        guard mxc.hasPrefix("mxc://") else { return nil }
        let path = String(mxc.dropFirst(6))
        let base = homeserver.hasSuffix("/") ? String(homeserver.dropLast()) : homeserver
        return URL(string: "\(base)/_matrix/media/v3/thumbnail/\(path)?width=64&height=64&method=crop")
    }
}
