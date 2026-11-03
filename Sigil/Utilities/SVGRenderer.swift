import AppKit

/// Renders SVG strings to bitmaps via macOS's native SVG support (NSImage(data:)).
/// Draws into its own bitmap context, so it's safe to call off the main thread.
enum SVGRenderer {

    // MARK: - Thumbnail Cache

    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 2000             // Keep up to 2000 rendered thumbnails
        cache.totalCostLimit = 50_000_000   // ~50 MB ceiling
        return cache
    }()

    static func cachedThumbnail(for key: String) -> NSImage? {
        thumbnailCache.object(forKey: key as NSString)
    }

    /// Get or render a cached thumbnail for the grid (rendered at 2x for Retina).
    static func thumbnail(for key: String, svgString: String, size: CGFloat) -> NSImage? {
        if let cached = cachedThumbnail(for: key) { return cached }
        guard let rendered = renderToImage(svgString: svgString, size: NSSize(width: size, height: size)) else { return nil }
        thumbnailCache.setObject(rendered, forKey: key as NSString, cost: Int(size * size * 16))
        return rendered
    }

    // MARK: - Core Rendering

    /// Render to an NSImage of `size` points backed by a 2x bitmap.
    static func renderToImage(svgString: String, size: NSSize, scale: CGFloat = 2) -> NSImage? {
        guard let rep = renderBitmap(svgString: svgString, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale)) else {
            return nil
        }
        rep.size = size
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// PNG data at an exact pixel size, independent of the current screen's scale.
    static func renderPNG(svgString: String, pixels: CGFloat) -> Data? {
        renderBitmap(svgString: svgString, pixelsWide: Int(pixels), pixelsHigh: Int(pixels))?
            .representation(using: .png, properties: [:])
    }

    private static func renderBitmap(svgString: String, pixelsWide: Int, pixelsHigh: Int) -> NSBitmapImageRep? {
        guard let data = svgString.data(using: .utf8),
              let svgImage = NSImage(data: data),
              svgImage.size.width > 0, svgImage.size.height > 0,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        svgImage.draw(in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
