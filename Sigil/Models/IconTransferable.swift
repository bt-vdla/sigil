import SwiftUI
import UniformTypeIdentifiers

/// A Transferable wrapper for icon drag-and-drop.
/// Provides multiple representations so the receiving app can pick the best type:
///   - File URL (.svg temp file) → Finder, file managers
///   - PNG data → Design apps, visual editors
///   - Plain text (SVG code) → Code editors, text fields
struct IconTransferable: Transferable {
    let icon: IconModel

    static var transferRepresentation: some TransferRepresentation {
        // 1. File representation: write a temp .svg file
        //    Receiving apps that understand files (Finder, IDEs) prefer this.
        FileRepresentation(exportedContentType: .svg) { transferable in
            let url = CopyService.writeTempSVG(icon: transferable.icon)
            return SentTransferredFile(url)
        }

        // 2. Data representation: PNG image bytes
        //    Visual apps (PowerPoint, Keynote, Sketch) prefer this.
        DataRepresentation(exportedContentType: .png) { transferable in
            guard let image = SVGRenderer.renderToImage(
                svgString: transferable.icon.svgString,
                size: NSSize(width: 128, height: 128)
            ),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                // Return SVG bytes as fallback
                return transferable.icon.svgString.data(using: .utf8) ?? Data()
            }
            return pngData
        }

        // 3. Plain text: raw SVG code
        //    Text editors, terminals, and anything that accepts text.
        ProxyRepresentation(exporting: \.icon.svgString)
    }
}
