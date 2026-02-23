import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.sigil.app", category: "IconStore")

@Observable
final class IconStore: @unchecked Sendable {
    // MARK: - Published State

    private(set) var allIcons: [IconModel] = []
    private(set) var isLoading = true
    private(set) var loadedPackCounts: [IconPack: Int] = [:]

    // Pre-filtered arrays by pack — avoids re-filtering 8k icons on every search
    private var iconsByPack: [IconPack: [IconModel]] = [:]

    // MARK: - Computed

    var totalCount: Int { allIcons.count }

    // MARK: - Loading built-ins

    func loadIcons() async {
        let result = await Task.detached(priority: .userInitiated) {
            var all: [IconModel] = []
            var counts: [IconPack: Int] = [:]
            var byPack: [IconPack: [IconModel]] = [:]

            for pack in IconPack.builtIns {
                let packIcons = Self.loadBuiltInPack(pack)
                counts[pack] = packIcons.count
                byPack[pack] = packIcons.sorted { $0.name < $1.name }
                all.append(contentsOf: packIcons)
            }

            all.sort { $0.name < $1.name }
            return (all, counts, byPack)
        }.value

        await MainActor.run {
            self.allIcons = result.0
            self.loadedPackCounts = result.1
            self.iconsByPack = result.2
            self.isLoading = false
        }
    }

    // MARK: - Loading custom packs

    func loadCustomPack(_ pack: IconPack, svgDirectory: URL) async {
        let icons = await Task.detached(priority: .userInitiated) {
            Self.loadSVGsFromDirectory(pack, directory: svgDirectory)
                .sorted { $0.name < $1.name }
        }.value

        await MainActor.run {
            // Remove any stale entries from a previous load of the same pack
            allIcons.removeAll { $0.pack.id == pack.id }
            iconsByPack[pack] = icons
            allIcons.append(contentsOf: icons)
            allIcons.sort { $0.name < $1.name }
            loadedPackCounts[pack] = icons.count
        }
    }

    func unloadCustomPack(id: String) {
        guard let pack = loadedPackCounts.keys.first(where: { $0.id == id }) else { return }
        iconsByPack.removeValue(forKey: pack)
        allIcons.removeAll { $0.pack.id == id }
        loadedPackCounts.removeValue(forKey: pack)
    }

    // MARK: - Private loading helpers

    private static func loadBuiltInPack(_ pack: IconPack) -> [IconModel] {
        guard let resourceURL = Bundle.main.resourceURL else {
            logger.error("Failed to locate bundle resource URL")
            return []
        }
        let iconsDir = resourceURL
            .appendingPathComponent("Icons", isDirectory: true)
            .appendingPathComponent(pack.directoryName, isDirectory: true)
            .standardized

        guard FileManager.default.fileExists(atPath: iconsDir.path) else {
            logger.error("Missing icon directory: \(iconsDir.path, privacy: .public)")
            return []
        }
        return loadSVGsFromDirectory(pack, directory: iconsDir)
    }

    private static func loadSVGsFromDirectory(_ pack: IconPack, directory: URL) -> [IconModel] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            logger.error("Failed to read contents of: \(directory.path, privacy: .public)")
            return []
        }

        return files.compactMap { url -> IconModel? in
            guard url.pathExtension.lowercased() == "svg",
                  let svgString = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return IconModel(name: url.deletingPathExtension().lastPathComponent, pack: pack, svgString: svgString)
        }
    }

    // MARK: - Search

    /// Fuzzy search across all icons. Returns all icons for the given pack when query is empty.
    /// Uses pre-filtered pack arrays to avoid re-filtering the full 8k set.
    func search(query: String, pack: IconPack? = nil) -> [IconModel] {
        let base: [IconModel]
        if let pack {
            base = iconsByPack[pack] ?? []
        } else {
            base = allIcons
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        // Detect bulk mode: comma, newline, or "+" separated list
        let separators = CharacterSet(charactersIn: ",+\n")
        let terms = trimmed
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        if terms.count > 1 {
            return bulkSearch(terms: terms, in: base)
        }

        return fuzzySearch(term: terms[0], in: base)
    }

    /// Single-term fuzzy search using pre-computed lowercased names.
    private func fuzzySearch(term: String, in icons: [IconModel]) -> [IconModel] {
        let lowered = term.lowercased()
        var scored: [(icon: IconModel, score: Int)] = []
        scored.reserveCapacity(icons.count / 4)

        for icon in icons {
            let nameLC = icon.nameLowercased

            if nameLC == lowered {
                scored.append((icon, 1000)); continue
            }
            if nameLC.hasPrefix(lowered) {
                scored.append((icon, 800)); continue
            }
            if icon.searchTokens.contains(where: { $0.hasPrefix(lowered) }) {
                scored.append((icon, 600)); continue
            }
            if nameLC.contains(lowered) {
                scored.append((icon, 400)); continue
            }
            if fuzzyMatch(query: lowered, target: nameLC) {
                scored.append((icon, 200)); continue
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.icon)
    }

    /// Bulk search: strict matching only — exact name, prefix, or token match.
    private func bulkSearch(terms: [String], in icons: [IconModel]) -> [IconModel] {
        let termSet = Set(terms)
        var matched: [IconModel] = []

        for icon in icons {
            let nameLC = icon.nameLowercased

            if termSet.contains(nameLC) {
                matched.append(icon)
                continue
            }

            for term in terms {
                if nameLC.hasPrefix(term + "-") ||
                   nameLC.hasSuffix("-" + term) ||
                   nameLC.contains("-" + term + "-") ||
                   icon.searchTokens.contains(term) {
                    matched.append(icon)
                    break
                }
            }
        }
        return matched
    }

    /// Simple fuzzy: all query characters appear in target in order.
    private func fuzzyMatch(query: String, target: String) -> Bool {
        var qi = query.startIndex
        var ti = target.startIndex
        while qi < query.endIndex && ti < target.endIndex {
            if query[qi] == target[ti] {
                qi = query.index(after: qi)
            }
            ti = target.index(after: ti)
        }
        return qi == query.endIndex
    }
}
