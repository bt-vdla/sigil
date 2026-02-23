import Foundation

struct IconPack: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var displayName: String
    var accentHex: String
    let isBuiltIn: Bool
    let directoryName: String

    // MARK: - Built-ins

    static let lucide = IconPack(
        id: "lucide",
        displayName: "Lucide",
        accentHex: "#F56565",
        isBuiltIn: true,
        directoryName: "lucide"
    )

    static let phosphor = IconPack(
        id: "phosphor",
        displayName: "Phosphor",
        accentHex: "#68D391",
        isBuiltIn: true,
        directoryName: "phosphor"
    )

    static let radix = IconPack(
        id: "radix",
        displayName: "Radix",
        accentHex: "#805AD5",
        isBuiltIn: true,
        directoryName: "radix"
    )

    static let tabler = IconPack(
        id: "tabler",
        displayName: "Tabler",
        accentHex: "#4299E1",
        isBuiltIn: true,
        directoryName: "tabler"
    )

    static var builtIns: [IconPack] { [.lucide, .phosphor, .radix, .tabler] }

    // MARK: - Factory for custom packs

    static func makeCustom(
        id: String = UUID().uuidString,
        displayName: String,
        accentHex: String = "#A0AEC0",
        directoryName: String
    ) -> IconPack {
        IconPack(id: id, displayName: displayName, accentHex: accentHex, isBuiltIn: false, directoryName: directoryName)
    }

    // MARK: - Hashable / Equatable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: IconPack, rhs: IconPack) -> Bool {
        lhs.id == rhs.id
    }
}
