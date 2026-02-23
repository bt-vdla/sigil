import SwiftUI

/// User-configurable icon appearance settings.
/// Applied as SVG string transforms before copy/render.
@Observable
final class IconCustomization {
    var strokeWidth: Double = 2.0       // Default for most icon packs
    var color: Color = .white           // currentColor replacement
    var isCustomized: Bool = false      // True when user has changed any setting

    // Predefined color palette for quick selection
    static let presetColors: [Color] = [
        .white, .black,
        Color(hex: "#EF4444"),  // Red
        Color(hex: "#F97316"),  // Orange
        Color(hex: "#EAB308"),  // Yellow
        Color(hex: "#22C55E"),  // Green
        Color(hex: "#3B82F6"),  // Blue
        Color(hex: "#8B5CF6"),  // Purple
        Color(hex: "#EC4899"),  // Pink
        Color(hex: "#6B7280"),  // Gray
    ]

    /// Apply customization to an SVG string.
    /// Replaces currentColor and stroke-width attributes.
    func apply(to svgString: String) -> String {
        guard isCustomized else { return svgString }

        var result = svgString

        // Replace color: currentColor → hex value
        let hexColor = color.hexString
        result = result.replacingOccurrences(of: "currentColor", with: hexColor)

        // Replace stroke-width with regex-like approach
        // Matches: stroke-width="<number>" (handles integers and decimals)
        if let range = result.range(of: #"stroke-width="[^"]*""#, options: .regularExpression) {
            result = result.replacingCharacters(
                in: range,
                with: "stroke-width=\"\(String(format: "%.1f", strokeWidth))\""
            )
        }

        // If the SVG uses stroke-width as a style attribute instead of XML attribute
        if let range = result.range(of: #"stroke-width:\s*[^;}"]*"#, options: .regularExpression) {
            result = result.replacingCharacters(
                in: range,
                with: "stroke-width: \(String(format: "%.1f", strokeWidth))"
            )
        }

        return result
    }

    func reset() {
        strokeWidth = 2.0
        color = .white
        isCustomized = false
    }
}

// MARK: - Color → Hex String

extension Color {
    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
