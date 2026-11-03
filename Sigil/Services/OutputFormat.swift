import AppKit

/// What a copy puts on the clipboard. Sigil remembers the last one used in each app.
enum OutputFormat: String, CaseIterable, Identifiable {
    case svg
    case component
    case importLine
    case inlineComponent
    case png1x
    case png2x
    case png3x
    case dataURI
    case file

    var id: String { rawValue }

    /// PNG @1x size in pixels.
    static let pngBase: CGFloat = 48

    var label: String {
        switch self {
        case .svg: "SVG"
        case .component: "Component"
        case .importLine: "Import line"
        case .inlineComponent: "Inline TSX"
        case .png1x: "PNG @1x"
        case .png2x: "PNG @2x"
        case .png3x: "PNG @3x"
        case .dataURI: "CSS data URI"
        case .file: "File"
        }
    }

    var symbol: String {
        switch self {
        case .svg: "chevron.left.forwardslash.chevron.right"
        case .component, .importLine, .inlineComponent: "curlybraces"
        case .png1x, .png2x, .png3x: "photo"
        case .dataURI: "number"
        case .file: "doc"
        }
    }

    var pngPixels: CGFloat? {
        switch self {
        case .png1x: Self.pngBase
        case .png2x: Self.pngBase * 2
        case .png3x: Self.pngBase * 3
        default: nil
        }
    }

    func isAvailable(for icon: IconModel) -> Bool {
        switch self {
        case .component, .importLine: IconPackage.for(icon.pack) != nil
        default: true
        }
    }

    /// Label with the library name where it matters: "Component · lucide-react".
    func label(for icon: IconModel) -> String {
        guard self == .component || self == .importLine, let pkg = IconPackage.for(icon.pack) else { return label }
        return "\(label) · \(pkg.module)"
    }

    // MARK: - Text output

    /// Clipboard text for this format, or nil for image/file formats.
    /// `svg` is the icon's markup with customization already applied.
    func text(for icon: IconModel, svg: String, customization: IconCustomization) -> String? {
        switch self {
        case .svg:
            return Self.clean(svg)
        case .component:
            return IconPackage.for(icon.pack)?.usage(icon.name, customization: customization)
        case .importLine:
            return IconPackage.for(icon.pack)?.importLine(icon.name)
        case .inlineComponent:
            return Self.tsxComponent(name: icon.name, svg: Self.clean(svg))
        case .dataURI:
            return Self.dataURI(Self.clean(svg))
        case .png1x, .png2x, .png3x, .file:
            return nil
        }
    }

    /// Drops the XML prolog, doctype and comments that packs ship but nobody wants pasted.
    static func clean(_ svg: String) -> String {
        svg
            .replacingOccurrences(of: #"<\?xml[^>]*\?>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<!DOCTYPE[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tsxComponent(name: String, svg: String) -> String {
        var jsx = svg
            .replacingOccurrences(of: " class=", with: " className=")
            .replacingOccurrences(of: "xlink:href", with: "xlinkHref")
            .replacingOccurrences(of: "xmlns:xlink", with: "xmlnsXlink")
        // stroke-width → strokeWidth (React warns on kebab-case SVG attributes); data-/aria- stay as they are
        let attribute = try! NSRegularExpression(pattern: #"(\s)((?!data-|aria-)[a-z]+(?:-[a-z]+)+)="#)
        for match in attribute.matches(in: jsx, range: NSRange(jsx.startIndex..., in: jsx)).reversed() {
            guard let range = Range(match.range(at: 2), in: jsx) else { continue }
            jsx.replaceSubrange(range, with: camelCase(String(jsx[range])))
        }
        // Spread props last on the root so callers can override size, className, onClick…
        if let open = jsx.range(of: "<svg"), let end = jsx.range(of: ">", range: open.upperBound..<jsx.endIndex) {
            let attributes = jsx[..<end.lowerBound].replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            jsx = attributes + " {...props}" + jsx[end.lowerBound...]
        }
        // ponytail: inline style="" strings stay as-is; none of the bundled packs use them

        let body = jsx.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }.joined(separator: "\n")
        return """
        export function \(componentName(name, suffix: "Icon"))(props: React.SVGProps<SVGSVGElement>) {
          return (
        \(body)
          );
        }
        """
    }

    static func dataURI(_ svg: String) -> String {
        let minified = svg
            .replacingOccurrences(of: #">\s+<"#, with: "><", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "'")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: " -_.!~*'()/=:;,+?@&$[]")
        let encoded = minified.addingPercentEncoding(withAllowedCharacters: allowed) ?? minified
        return "url(\"data:image/svg+xml,\(encoded)\")"
    }

    // MARK: - Names

    /// "trash-2" → "Trash2"; prefixes "Icon" when the name would start with a digit.
    static func pascalCase(_ name: String) -> String {
        name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
    }

    static func componentName(_ name: String, prefix: String = "", suffix: String = "") -> String {
        let base = prefix + pascalCase(name) + suffix
        return base.first?.isNumber == true ? "Icon" + base : base
    }

    static func camelCase(_ kebab: String) -> String {
        let parts = kebab.split(separator: "-")
        return parts.enumerated().map { $0 == 0 ? String($1) : $1.prefix(1).uppercased() + $1.dropFirst() }.joined()
    }

    // MARK: - Per-app memory

    /// Last format used in that app, or a sensible default for its kind.
    static func preferred(for app: NSRunningApplication?) -> OutputFormat {
        if let id = app?.bundleIdentifier,
           let raw = (UserDefaults.standard.dictionary(forKey: "formatByApp") as? [String: String])?[id],
           let format = OutputFormat(rawValue: raw) {
            return format
        }
        return CopyService.category(of: app) == .design ? .file : .svg
    }

    static func remember(_ format: OutputFormat, for app: NSRunningApplication?) {
        guard let id = app?.bundleIdentifier else { return }
        var map = UserDefaults.standard.dictionary(forKey: "formatByApp") as? [String: String] ?? [:]
        map[id] = format.rawValue
        UserDefaults.standard.set(map, forKey: "formatByApp")
    }

    /// The format a copy of this icon would use right now.
    static func effective(for icon: IconModel, app: NSRunningApplication?) -> OutputFormat {
        let format = preferred(for: app)
        return format.isAvailable(for: icon) ? format : .svg
    }
}

// MARK: - Icon libraries

/// The React package that ships each built-in pack, and how it names components.
struct IconPackage {
    let module: String
    let prefix: String
    let suffix: String
    let strokeProp: String?

    static func `for`(_ pack: IconPack) -> IconPackage? {
        switch pack.id {
        case "lucide": IconPackage(module: "lucide-react", prefix: "", suffix: "", strokeProp: "strokeWidth")
        case "tabler": IconPackage(module: "@tabler/icons-react", prefix: "Icon", suffix: "", strokeProp: "stroke")
        case "phosphor": IconPackage(module: "@phosphor-icons/react", prefix: "", suffix: "Icon", strokeProp: nil)
        case "radix": IconPackage(module: "@radix-ui/react-icons", prefix: "", suffix: "Icon", strokeProp: nil)
        default: nil
        }
    }

    func componentName(_ name: String) -> String {
        OutputFormat.componentName(name, prefix: prefix, suffix: suffix)
    }

    func importLine(_ name: String) -> String {
        "import { \(componentName(name)) } from \"\(module)\";"
    }

    /// `<Trash2 strokeWidth={1.5} color="#EF4444" />`, carrying customization over as props.
    func usage(_ name: String, customization: IconCustomization) -> String {
        var props: [String] = []
        if let strokeProp, customization.strokeWidth != IconCustomization.defaultStrokeWidth {
            props.append("\(strokeProp)={\(String(format: "%g", customization.strokeWidth))}")
        }
        if let color = customization.color {
            props.append("color=\"\(color.hexString)\"")
        }
        return "<\(([componentName(name)] + props).joined(separator: " ")) />"
    }
}
