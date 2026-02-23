import AppKit

/// Renders SVG strings to NSImage natively via CoreGraphics.
/// Maintains an NSCache for grid thumbnails to avoid redundant rendering.
enum SVGRenderer {

    // MARK: - Thumbnail Cache

    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 2000             // Keep up to 2000 rendered thumbnails
        cache.totalCostLimit = 50_000_000   // ~50 MB ceiling
        return cache
    }()

    /// Get or render a cached thumbnail for the grid.
    static func thumbnail(for iconID: String, svgString: String, size: CGFloat = 28) -> NSImage? {
        let cacheKey = "\(iconID)@\(Int(size))" as NSString

        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        guard let rendered = renderToImage(svgString: svgString, size: NSSize(width: size, height: size)) else {
            return nil
        }

        thumbnailCache.setObject(rendered, forKey: cacheKey, cost: Int(size * size * 4))
        return rendered
    }

    /// Evict all cached thumbnails (e.g. on memory warning).
    static func clearCache() {
        thumbnailCache.removeAllObjects()
    }

    // MARK: - Core Rendering

    /// Render an SVG string to an NSImage at the given point size.
    /// Uses macOS native SVG support via NSImage(data:) — no WebView needed.
    static func renderToImage(svgString: String, size: NSSize) -> NSImage? {
        guard let data = svgString.data(using: .utf8),
              let svgImage = NSImage(data: data) else { return nil }

        guard svgImage.size.width > 0 && svgImage.size.height > 0 else { return nil }

        let targetImage = NSImage(size: size)
        targetImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        svgImage.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: svgImage.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        targetImage.unlockFocus()
        return targetImage
    }
}
