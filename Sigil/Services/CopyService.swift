import AppKit
import UniformTypeIdentifiers

/// Handles all clipboard operations, app detection, and drag payload creation.
final class CopyService {

    // MARK: - App Detection

    enum AppCategory {
        case design
        case code
        case other
    }

    private static let designBundleIDs: Set<String> = [
        "com.figma.Desktop",
        "com.bohemiancoding.sketch3",
        "com.seriflabs.affinitydesigner",
        "com.seriflabs.affinitydesigner2",
        "com.microsoft.Powerpoint",
        "com.apple.iWork.Keynote",
        "com.canva.CanvaDesktop",
        "com.adobe.illustrator",
        "com.adobe.Photoshop",
    ]

    private static let codeBundleIDs: Set<String> = [
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "dev.zed.Zed",
        "com.panic.Nova",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "net.kovidgoyal.kitty",
    ]

    static func detectFrontmostAppCategory() -> AppCategory {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else {
            return .other
        }

        if designBundleIDs.contains(bundleID) { return .design }
        if codeBundleIDs.contains(bundleID) { return .code }
        return .other
    }

    // MARK: - Smart Copy (single click)

    /// For design apps: copy as SVG file reference (vector, not rasterized).
    /// PowerPoint, Keynote, etc. import the .svg natively and keep it scalable.
    /// For code apps / everything else: copy raw SVG code string.
    static func smartCopy(icon: IconModel) {
        switch detectFrontmostAppCategory() {
        case .design:
            copyFile(icon: icon)
        case .code, .other:
            copySVGCode(icon: icon)
        }
    }

    // MARK: - Explicit Copy Actions

    static func copySVGCode(icon: IconModel) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(icon.svgString, forType: .string)
    }

    static func copyAsPNG(icon: IconModel, size: CGFloat = 64) {
        guard let pngData = renderPNG(svgString: icon.svgString, size: size) else {
            copySVGCode(icon: icon)
            return
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(pngData, forType: .png)

        // Also set TIFF — some apps (Preview, Keynote) prefer TIFF over PNG
        if let image = NSImage(data: pngData), let tiff = image.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    static func copyAsReactComponent(icon: IconModel) {
        let componentName = icon.name
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()

        let indentedSVG = icon.svgString
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "      \($0)" }
            .joined(separator: "\n")

        let component = """
        import React from 'react';

        const \(componentName) = (props) => (
        \(indentedSVG)
        );

        export default \(componentName);
        """

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(component, forType: .string)
    }

    /// Copy as file reference WITH image data fallback.
    /// Receiving app picks whichever type it supports:
    ///   - Finder/Terminal → file URL
    ///   - PowerPoint/Keynote → TIFF/PNG image
    ///   - Text editors → SVG string
    static func copyFile(icon: IconModel) {
        let tempURL = writeTempSVG(icon: icon)
        let pb = NSPasteboard.general
        pb.clearContents()

        // File URL for Finder-style paste
        pb.writeObjects([tempURL as NSURL])

        // Also put image data on the pasteboard so visual apps can paste the icon
        // as an image. This is why "Copy File → Paste in PowerPoint" now shows the icon.
        if let pngData = renderPNG(svgString: icon.svgString, size: 128) {
            pb.setData(pngData, forType: .png)
            if let image = NSImage(data: pngData), let tiff = image.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }
    }

    // MARK: - Bulk Copy

    /// Write all selected icons to a uniquely-named temp folder and reveal in Finder.
    /// This is the most reliable way to bulk-transfer SVGs into design apps —
    /// the user drags from the revealed Finder window into PowerPoint/Keynote/etc.
    @discardableResult
    static func bulkExportAndReveal(icons: [IconModel]) -> URL? {
        guard !icons.isEmpty else { return nil }

        // Create a timestamped export folder so batches don't overwrite each other
        let timestamp = Int(Date().timeIntervalSince1970)
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sigil/export-\(timestamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Write each icon as an SVG file
        var fileURLs: [URL] = []
        for icon in icons {
            let fileURL = exportDir.appendingPathComponent("\(icon.name).svg")
            try? icon.svgString.write(to: fileURL, atomically: true, encoding: .utf8)
            fileURLs.append(fileURL)
        }

        // Also put concatenated SVG code on the pasteboard (for code editors)
        let pb = NSPasteboard.general
        pb.clearContents()
        let combined = icons.map(\.svgString).joined(separator: "\n\n")
        pb.setString(combined, forType: .string)

        // Put all file URLs on the pasteboard too (Finder can paste them)
        pb.writeObjects(fileURLs.map { $0 as NSURL })

        // Reveal the folder in Finder — select all exported files
        if !fileURLs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
        }

        return exportDir
    }

    /// Copy multiple icons as concatenated SVG code strings (for code editors).
    static func bulkCopySVGCode(icons: [IconModel]) {
        guard !icons.isEmpty else { return }
        let combined = icons.map(\.svgString).joined(separator: "\n\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(combined, forType: .string)
    }

    /// Copy multiple icons as SVG file references — no Finder reveal.
    /// Puts all file URLs on the pasteboard so design apps can paste them
    /// as scalable vector icons (same mechanism as single `copyFile`, but N files).
    /// Also layers PNG + TIFF of the first icon as an image fallback for apps
    /// that only accept one image at a time via paste.
    static func bulkCopyFiles(icons: [IconModel]) {
        guard !icons.isEmpty else { return }

        // Write each icon to a shared Sigil temp dir
        let fileURLs: [URL] = icons.compactMap { icon in
            let url = writeTempSVG(icon: icon)
            return url
        }

        let pb = NSPasteboard.general
        pb.clearContents()

        // All file URLs — Finder-style apps and vector design tools pick these up
        pb.writeObjects(fileURLs.map { $0 as NSURL })

        // Image fallback: render a composite strip or just the first icon.
        // Most apps that handle paste-as-image only take a single image anyway,
        // so we use the first icon's rendered data as the visual preview.
        if let pngData = renderPNG(svgString: icons[0].svgString, size: 128) {
            pb.setData(pngData, forType: .png)
            if let image = NSImage(data: pngData), let tiff = image.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }
    }

    // MARK: - Helpers

    /// Render SVG to PNG data at the given point size.
    private static func renderPNG(svgString: String, size: CGFloat) -> Data? {
        guard let image = SVGRenderer.renderToImage(
            svgString: svgString,
            size: NSSize(width: size, height: size)
        ) else { return nil }

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: - Temp File

    static func writeTempSVG(icon: IconModel) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sigil", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appendingPathComponent("\(icon.name).svg")
        try? icon.svgString.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Write a temp PNG file and return its URL.
    static func writeTempPNG(icon: IconModel, size: CGFloat = 128) -> URL? {
        guard let pngData = renderPNG(svgString: icon.svgString, size: size) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sigil", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appendingPathComponent("\(icon.name).png")
        try? pngData.write(to: fileURL, options: .atomic)
        return fileURL
    }
}
