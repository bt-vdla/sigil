import Foundation
import AppKit
import Observation

@Observable
final class CustomPackStore {

    // MARK: - State

    private(set) var packs: [IconPack] = []
    var importProgress: ImportProgress = .idle

    /// User-defined display order: array of pack IDs (built-in + custom combined).
    var packOrder: [String] = []

    /// IDs of packs hidden from the main icon picker.
    var hiddenPackIds: Set<String> = []

    var githubToken: String {
        get { UserDefaults.standard.string(forKey: "sigilGitHubToken") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "sigilGitHubToken") }
    }

    // MARK: - Derived pack collections

    /// All packs (built-in + custom) in user order.
    var allPacksOrdered: [IconPack] {
        let all = IconPack.builtIns + packs
        guard !packOrder.isEmpty else { return all }
        let dict = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var ordered = packOrder.compactMap { dict[$0] }
        let known = Set(packOrder)
        ordered += all.filter { !known.contains($0.id) }   // append any not yet in the stored order
        return ordered
    }

    /// Packs visible in the main icon picker (non-hidden, in order).
    var visiblePacksOrdered: [IconPack] {
        allPacksOrdered.filter { !hiddenPackIds.contains($0.id) }
    }

    // MARK: - Callbacks (wired by AppDelegate)

    var onPackAdded: ((IconPack) -> Void)?
    var onPackRemoved: ((String) -> Void)?

    // MARK: - Directory layout

    private let fileManager = FileManager.default

    let packsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Packs", isDirectory: true)
    }()

    func packDirectory(for id: String) -> URL {
        packsDirectory.appendingPathComponent(id, isDirectory: true)
    }

    // MARK: - Load from disk

    func loadFromDisk() {
        try? fileManager.createDirectory(at: packsDirectory, withIntermediateDirectories: true)

        // Restore ordering and visibility state
        packOrder    = UserDefaults.standard.stringArray(forKey: "sigilPackOrder")  ?? []
        hiddenPackIds = Set(UserDefaults.standard.stringArray(forKey: "sigilHiddenPacks") ?? [])

        guard let entries = try? fileManager.contentsOfDirectory(
            at: packsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let loaded: [IconPack] = entries.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            let metaURL = url.appendingPathComponent(".sigil-pack.json")
            guard fileManager.fileExists(atPath: metaURL.path),
                  let data = try? Data(contentsOf: metaURL),
                  let pack = try? JSONDecoder().decode(IconPack.self, from: data) else { return nil }
            guard !IconPack.builtIns.contains(where: { $0.id == pack.id }) else { return nil }
            return pack
        }

        // Keep load order stable; display order is controlled by packOrder
        packs = loaded
    }

    // MARK: - Icon count

    func svgCount(for pack: IconPack) -> Int {
        let dir = packDirectory(for: pack.id)
        guard let files = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return files.filter { $0.pathExtension.lowercased() == "svg" }.count
    }

    // MARK: - Import: local folder

    @discardableResult
    func importFromFolder(_ sourceURL: URL, normalizeColors: Bool = true) throws -> IconPack {
        _ = sourceURL.startAccessingSecurityScopedResource()
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let folderName = sourceURL.deletingPathExtension().lastPathComponent
        let id = UUID().uuidString
        let destDir = packDirectory(for: id)

        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

        let svgFiles: [URL]
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            svgFiles = contents.filter { $0.pathExtension.lowercased() == "svg" }
        } catch {
            try? fileManager.removeItem(at: destDir)
            throw ImportError.directoryAccessDenied
        }

        guard !svgFiles.isEmpty else {
            try? fileManager.removeItem(at: destDir)
            throw ImportError.noSVGsFound
        }

        for svgURL in svgFiles {
            var content = (try? String(contentsOf: svgURL, encoding: .utf8)) ?? ""
            if normalizeColors { content = Self.normalizeColors(content) }
            let destURL = destDir.appendingPathComponent(svgURL.lastPathComponent)
            try content.write(to: destURL, atomically: true, encoding: .utf8)
        }

        let pack = IconPack.makeCustom(id: id, displayName: folderName, directoryName: id)
        try writeMetadata(pack, to: destDir)
        replaceDuplicate(displayName: folderName)

        packs.append(pack)
        appendToOrder(pack.id)
        onPackAdded?(pack)
        return pack
    }

    // MARK: - Import: remote URL / npm / GitHub

    func importFromRemote(_ input: String) async {
        await MainActor.run { importProgress = .resolving }

        let id = UUID().uuidString
        let destDir = packDirectory(for: id)

        do {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

            let svgFiles: [(name: String, content: String)]
            let displayName: String

            switch PackImporter.detectSource(input) {
            case .npm(let package):
                svgFiles = try await PackImporter.resolveNPM(package) { current, total in
                    Task { @MainActor in self.importProgress = .downloading(current: current, total: total) }
                }
                displayName = Self.displayNameFromInput(input)

            case .github(let owner, let repo, let path):
                svgFiles = try await PackImporter.resolveGitHub(
                    owner: owner, repo: repo, path: path,
                    token: githubToken.isEmpty ? nil : githubToken
                ) { current, total in
                    Task { @MainActor in self.importProgress = .downloading(current: current, total: total) }
                }
                displayName = repo

            case .zipURL(let url):
                svgFiles = try await PackImporter.resolveZIP(url: url) { current, total in
                    Task { @MainActor in self.importProgress = .downloading(current: current, total: total) }
                }
                displayName = Self.displayNameFromInput(input)

            case nil:
                try? fileManager.removeItem(at: destDir)
                await MainActor.run {
                    importProgress = .failed("Couldn't recognize this source. Try a GitHub URL, npm package name (e.g. lucide-react), or a .zip link.")
                }
                return
            }

            guard !svgFiles.isEmpty else {
                try? fileManager.removeItem(at: destDir)
                await MainActor.run { importProgress = .failed("No SVG icons found at this source.") }
                return
            }

            await MainActor.run { importProgress = .normalizing }

            for file in svgFiles {
                let normalized = Self.normalizeColors(file.content)
                let filename = file.name.hasSuffix(".svg") ? file.name : "\(file.name).svg"
                let destURL = destDir.appendingPathComponent(filename)
                try normalized.write(to: destURL, atomically: true, encoding: .utf8)
            }

            let pack = IconPack.makeCustom(id: id, displayName: displayName, directoryName: id)
            try writeMetadata(pack, to: destDir)
            replaceDuplicate(displayName: displayName)

            await MainActor.run {
                packs.append(pack)
                appendToOrder(pack.id)
                importProgress = .done(pack)
                onPackAdded?(pack)
            }

        } catch let error as PackImporter.ImportError {
            try? fileManager.removeItem(at: destDir)
            await MainActor.run { importProgress = .failed(error.localizedDescription) }
        } catch {
            try? fileManager.removeItem(at: destDir)
            await MainActor.run { importProgress = .failed(error.localizedDescription) }
        }
    }

    // MARK: - Rename / Recolor

    func renamePack(_ id: String, to name: String) {
        guard let index = packs.firstIndex(where: { $0.id == id }) else { return }
        packs[index].displayName = name
        try? writeMetadata(packs[index], to: packDirectory(for: id))
        // No re-sort: display order is controlled by packOrder
    }

    func recolorPack(_ id: String, hex: String) {
        guard let index = packs.firstIndex(where: { $0.id == id }) else { return }
        packs[index].accentHex = hex
        try? writeMetadata(packs[index], to: packDirectory(for: id))
    }

    // MARK: - Remove

    func removePack(_ id: String) {
        try? fileManager.removeItem(at: packDirectory(for: id))
        packs.removeAll { $0.id == id }
        packOrder.removeAll { $0 == id }
        hiddenPackIds.remove(id)
        UserDefaults.standard.set(packOrder, forKey: "sigilPackOrder")
        UserDefaults.standard.set(Array(hiddenPackIds), forKey: "sigilHiddenPacks")
        onPackRemoved?(id)
    }

    // MARK: - Reorder

    /// Move `id` to just before `targetId` in the display order.
    /// Pass `nil` for `targetId` to append at the end.
    func movePack(_ id: String, before targetId: String?) {
        var ids = allPacksOrdered.map { $0.id }
        ids.removeAll { $0 == id }
        if let targetId, let idx = ids.firstIndex(of: targetId) {
            ids.insert(id, at: idx)
        } else {
            ids.append(id)
        }
        packOrder = ids
        UserDefaults.standard.set(ids, forKey: "sigilPackOrder")
    }

    // MARK: - Visibility

    func toggleVisibility(_ id: String) {
        if hiddenPackIds.contains(id) {
            hiddenPackIds.remove(id)
        } else {
            hiddenPackIds.insert(id)
        }
        UserDefaults.standard.set(Array(hiddenPackIds), forKey: "sigilHiddenPacks")
    }

    // MARK: - Reveal in Finder

    func revealInFinder(_ id: String) {
        NSWorkspace.shared.activateFileViewerSelecting([packDirectory(for: id)])
    }

    // MARK: - Private helpers

    private func writeMetadata(_ pack: IconPack, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pack)
        try data.write(to: directory.appendingPathComponent(".sigil-pack.json"), options: .atomic)
    }

    private func replaceDuplicate(displayName: String) {
        if let existing = packs.first(where: { $0.displayName.lowercased() == displayName.lowercased() }) {
            try? fileManager.removeItem(at: packDirectory(for: existing.id))
            packs.removeAll { $0.id == existing.id }
            packOrder.removeAll { $0 == existing.id }
            hiddenPackIds.remove(existing.id)
            onPackRemoved?(existing.id)
        }
    }

    /// Appends `id` to `packOrder` if not already present, then persists.
    private func appendToOrder(_ id: String) {
        guard !packOrder.contains(id) else { return }
        packOrder.append(id)
        UserDefaults.standard.set(packOrder, forKey: "sigilPackOrder")
    }

    // MARK: - Color normalization

    static func normalizeColors(_ svg: String) -> String {
        var result = svg
        let replacements: [(String, String)] = [
            ("fill=\"#000000\"", "fill=\"currentColor\""),
            ("fill=\"#000\"",    "fill=\"currentColor\""),
            ("fill=\"black\"",   "fill=\"currentColor\""),
            ("stroke=\"#000000\"", "stroke=\"currentColor\""),
            ("stroke=\"#000\"",    "stroke=\"currentColor\""),
            ("stroke=\"black\"",   "stroke=\"currentColor\""),
        ]
        for (old, new) in replacements {
            result = result.replacingOccurrences(of: old, with: new, options: .caseInsensitive)
        }
        return result
    }

    // MARK: - Helpers

    private static func displayNameFromInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.host?.contains("github.com") == true {
            let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if parts.count >= 2 { return parts[1] }
        }
        if trimmed.contains("/") {
            return String(trimmed.split(separator: "/").last ?? Substring(trimmed))
        }
        return trimmed
    }

    // MARK: - Progress enum

    enum ImportProgress: Equatable {
        case idle
        case resolving
        case downloading(current: Int, total: Int)
        case normalizing
        case done(IconPack)
        case failed(String)
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case noSVGsFound
        case directoryAccessDenied

        var errorDescription: String? {
            switch self {
            case .noSVGsFound: "No SVG files were found in the selected folder."
            case .directoryAccessDenied: "Could not read the selected folder. Please try again."
            }
        }
    }
}
