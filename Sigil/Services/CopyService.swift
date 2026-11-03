import AppKit
import UniformTypeIdentifiers

/// Handles all clipboard operations, app detection, and drag payload creation.
final class CopyService {

    // MARK: - App Detection

    enum AppCategory {
        case design
        case other
    }

    /// Apps that need a file or image on paste. Figma, Sketch and Illustrator are left out:
    /// they turn pasted SVG markup into editable vectors, which beats a PNG.
    private static let designBundleIDs: Set<String> = [
        "com.seriflabs.affinitydesigner",
        "com.seriflabs.affinitydesigner2",
        "com.microsoft.Powerpoint",
        "com.apple.iWork.Keynote",
        "com.canva.CanvaDesktop",
        "com.adobe.Photoshop",
    ]

    /// The app that was frontmost when the drawer opened (set by DrawerController).
    static var targetApp: NSRunningApplication?

    static func category(of app: NSRunningApplication?) -> AppCategory {
        guard let id = app?.bundleIdentifier, designBundleIDs.contains(id) else { return .other }
        return .design
    }

    // MARK: - Copy

    /// Puts the icon on the clipboard in the given format, with customization applied.
    static func copy(_ icon: IconModel, as format: OutputFormat, customization: IconCustomization) {
        let svg = customization.apply(to: icon.svgString)

        if let text = format.text(for: icon, svg: svg, customization: customization) {
            setString(text)
        } else if let pixels = format.pngPixels {
            copyPNG(svg: svg, pixels: pixels)
        } else {
            copyFile(icon: icon.withSVG(svg))
        }
    }

    private static func setString(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    private static func copyPNG(svg: String, pixels: CGFloat) {
        guard let pngData = SVGRenderer.renderPNG(svgString: svg, pixels: pixels) else {
            setString(OutputFormat.clean(svg))
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(pngData, forType: .png)
        // Also set TIFF — some apps (Preview, Keynote) prefer TIFF over PNG
        if let tiff = NSImage(data: pngData)?.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    /// Copy as file reference WITH image data fallback.
    /// Receiving app picks whichever type it supports:
    ///   - Finder/Terminal → file URL
    ///   - PowerPoint/Keynote → TIFF/PNG image
    static func copyFile(icon: IconModel) {
        let tempURL = writeTempSVG(icon: icon)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([tempURL as NSURL])

        if let pngData = SVGRenderer.renderPNG(svgString: icon.svgString, pixels: OutputFormat.pngBase * 2) {
            pb.setData(pngData, forType: .png)
            if let tiff = NSImage(data: pngData)?.tiffRepresentation {
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

        var fileURLs: [URL] = []
        for icon in icons {
            let fileURL = exportDir.appendingPathComponent("\(icon.name).svg")
            try? OutputFormat.clean(icon.svgString).write(to: fileURL, atomically: true, encoding: .utf8)
            fileURLs.append(fileURL)
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(icons.map { OutputFormat.clean($0.svgString) }.joined(separator: "\n\n"), forType: .string)
        pb.writeObjects(fileURLs.map { $0 as NSURL })

        if !fileURLs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
        }
        return exportDir
    }

    /// Copy multiple icons as concatenated SVG code strings (for code editors).
    static func bulkCopySVGCode(icons: [IconModel]) {
        guard !icons.isEmpty else { return }
        setString(icons.map { OutputFormat.clean($0.svgString) }.joined(separator: "\n\n"))
    }

    /// Copy multiple icons as SVG file references, plus the first icon as an image
    /// for apps that only take one image on paste.
    static func bulkCopyFiles(icons: [IconModel]) {
        guard let first = icons.first else { return }
        let fileURLs = icons.map(writeTempSVG)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(fileURLs.map { $0 as NSURL })

        if let pngData = SVGRenderer.renderPNG(svgString: first.svgString, pixels: OutputFormat.pngBase * 2) {
            pb.setData(pngData, forType: .png)
            if let tiff = NSImage(data: pngData)?.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }
    }

    // MARK: - Temp File

    static func writeTempSVG(icon: IconModel) -> URL {
        // One folder per pack so lucide:trash and tabler:trash don't overwrite each other
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sigil/\(icon.pack.directoryName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appendingPathComponent("\(icon.name).svg")
        try? OutputFormat.clean(icon.svgString).write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
