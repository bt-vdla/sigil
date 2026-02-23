import Foundation

struct IconModel: Identifiable, Hashable, Sendable {
    let id: String              // Unique: "pack:name" e.g. "lucide:arrow-left"
    let name: String            // Filename without extension, e.g. "arrow-left"
    let nameLowercased: String  // Pre-computed for search hot path — avoids 8k+ allocations per keystroke
    let displayName: String     // Human-readable, e.g. "Arrow Left"
    let pack: IconPack
    let svgString: String       // Raw SVG markup
    let tags: [String]          // Parsed from filename segments (split on dashes)

    /// Lowercase search tokens: name segments + pack name
    let searchTokens: [String]

    init(name: String, pack: IconPack, svgString: String) {
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

        // Tags derived from name segments for searchability
        let segments = self.nameLowercased
            .split(separator: "-")
            .map(String.init)
        self.tags = segments

        // Search tokens include segments and the pack name
        self.searchTokens = segments + [pack.displayName.lowercased()]
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: IconModel, rhs: IconModel) -> Bool {
        lhs.id == rhs.id
    }
}
