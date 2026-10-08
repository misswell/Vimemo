import UIKit
import ImageIO

/// Keeps decoded gallery images out of scrolling and glass animation transactions.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSString, UIImage>()
    private var pending: [String: Task<UIImage?, Never>] = [:]

    init(memoryLimit: Int = 32 * 1024 * 1024) {
        cache.totalCostLimit = memoryLimit
        cache.countLimit = 80
    }

    func image(for url: URL, maxPixelSize: Int = 1024) async -> UIImage? {
        guard let info = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let modified = (info[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (info[.size] as? NSNumber)?.intValue ?? 0
        let key = "\(url.absoluteString)|\(maxPixelSize)|\(modified)|\(size)"
        if let image = cache.object(forKey: key as NSString) { return image }
        if let task = pending[key] { return await task.value }
        let task = Task.detached(priority: .utility) {
            Self.decode(url, maxPixelSize: maxPixelSize)
        }
        pending[key] = task
        let image = await task.value
        pending[key] = nil
        if let image, let cgImage = image.cgImage {
            cache.setObject(image, forKey: key as NSString, cost: cgImage.bytesPerRow * cgImage.height)
        }
        return image
    }

    private nonisolated static func decode(_ url: URL, maxPixelSize: Int) -> UIImage? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }
    }
}
