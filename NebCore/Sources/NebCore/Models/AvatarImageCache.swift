import Foundation
import MatrixRustSDK
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
    private var clientProvider: (() -> Client?)?

    private init() {
        cache.countLimit = 200
    }

    public func setClientProvider(_ provider: @escaping () -> Client?) {
        self.clientProvider = provider
    }

    public func image(for mxcURL: String, homeserverURL: String = "") async -> PlatformImage? {
        if let cached = cache.object(forKey: mxcURL as NSString) {
            return cached
        }

        let existingTask: Task<PlatformImage?, Never>? = lock.withLock { inflight[mxcURL] }
        if let existing = existingTask {
            return await existing.value
        }

        let task = Task<PlatformImage?, Never> {
            guard let data = await self.downloadThumbnail(mxcURL: mxcURL) else { return nil }
            guard let image = PlatformImage(data: data) else { return nil }
            self.cache.setObject(image, forKey: mxcURL as NSString)
            return image
        }

        lock.withLock { inflight[mxcURL] = task }

        let result = await task.value

        _ = lock.withLock { inflight.removeValue(forKey: mxcURL) }

        return result
    }

    private func downloadThumbnail(mxcURL: String) async -> Data? {
        guard let client = clientProvider?() else { return nil }
        do {
            let source = try MediaSource.fromUrl(url: mxcURL)
            return try await client.getMediaThumbnail(mediaSource: source, width: 64, height: 64)
        } catch {
            return nil
        }
    }
}
