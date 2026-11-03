import Foundation

struct IconModel: Identifiable, Hashable, Sendable {
    let id: String              // Unique: "pack:name" e.g. "lucide:arrow-left"
    let name: String            // Filename without extension, e.g. "arrow-left"
    let nameLowercased: String  // Pre-computed for search hot path — avoids 8k+ allocations per keystroke
    let displayName: String     // Human-readable, e.g. "Arrow Left"
    let pack: IconPack
    let svgString: String       // Raw SVG markup

    /// Words from the filename: "arrow-left" → ["arrow", "left"]
    let nameWords: [String]
    /// The pack's published tags, split into words: trash → ["bin", "delete", "garbage", …]
    let keywords: Set<String>
    /// First letters of the name words: "arrow-left" → "al"
    let initials: String
    /// Name words + keywords as bytes, for typo matching without String overhead
    let tokenBytes: [[UInt8]]

    /// Lowercase search tokens: name segments + pack name
    let searchTokens: [String]

    init(name: String, pack: IconPack, svgString: String, keywords: [String] = []) {
        self.name = name
        self.pack = pack
        self.svgString = svgString
        self.id = "\(pack.directoryName):\(name)"
        self.nameLowercased = name.lowercased()

        // "arrow-left" → "Arrow Left"
        self.displayName = name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized

        let words = nameLowercased.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map(String.init)
        self.nameWords = words
        self.keywords = Set(keywords).subtracting(words)
        self.initials = String(words.compactMap(\.first))
        self.tokenBytes = (words + self.keywords).map { Array($0.utf8) }
        self.searchTokens = words + [pack.displayName.lowercased()]
    }

    /// Same icon with a transformed SVG (customization), keeping its search data.
    func withSVG(_ svg: String) -> IconModel {
        IconModel(name: name, pack: pack, svgString: svg, keywords: Array(keywords))
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: IconModel, rhs: IconModel) -> Bool {
        lhs.id == rhs.id
    }
}
