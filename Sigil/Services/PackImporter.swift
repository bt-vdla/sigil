import Foundation

enum PackImporter {

    // MARK: - Source detection

    enum Source {
        case npm(package: String)
        case github(owner: String, repo: String, path: String?)
        case zipURL(URL)
    }

    static func detectSource(_ input: String) -> Source? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // GitHub URL: https://github.com/owner/repo[/tree/branch/path]
        if let url = URL(string: trimmed), let host = url.host, host.contains("github.com") {
            let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            guard parts.count >= 2 else { return nil }
            let owner = parts[0]
            // Strip .git suffix so both "github.com/user/repo" and ".../repo.git" work
            let rawRepo = parts[1]
            let repo = rawRepo.hasSuffix(".git") ? String(rawRepo.dropLast(4)) : rawRepo
            var subpath: String? = nil
            // .../tree/<branch>/path → parts[2]=="tree", parts[3]==branch, parts[4...]==path
            if parts.count > 4, parts[2] == "tree" {
                let pathParts = parts.dropFirst(4)
                subpath = pathParts.isEmpty ? nil : pathParts.joined(separator: "/")
            }
            return .github(owner: owner, repo: repo, path: subpath)
        }

        // ZIP URL
        if trimmed.lowercased().hasSuffix(".zip"), let url = URL(string: trimmed) {
            return .zipURL(url)
        }

        // npm package name: plain name or scoped (@scope/name)
        let npmPattern = #"^(@[a-zA-Z0-9][a-zA-Z0-9._-]*/)?[a-zA-Z0-9][a-zA-Z0-9._-]*$"#
        if trimmed.range(of: npmPattern, options: .regularExpression) != nil {
            return .npm(package: trimmed)
        }

        return nil
    }

    // MARK: - npm via unpkg.com

    static func resolveNPM(
        _ package: String,
        progress: @escaping (Int, Int) -> Void
    ) async throws -> [(name: String, content: String)] {
        let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? package
        guard let metaURL = URL(string: "https://unpkg.com/\(encoded)@latest/?meta") else {
            throw ImportError.invalidURL
        }

        let (metaData, metaResponse) = try await URLSession.shared.data(from: metaURL)
        if let http = metaResponse as? HTTPURLResponse, http.statusCode == 404 {
            throw ImportError.packageNotFound(package)
        }

        let meta = try JSONDecoder().decode(UnpkgMeta.self, from: metaData)
        var svgPaths: [String] = []
        collectSVGPaths(from: meta, into: &svgPaths)

        guard !svgPaths.isEmpty else { throw ImportError.noSVGsFound }

        let urls = svgPaths.compactMap { URL(string: "https://unpkg.com/\(encoded)@latest\($0)") }
        return try await downloadFiles(urls: urls, progress: progress)
    }

    private static func collectSVGPaths(from node: UnpkgMeta, into paths: inout [String]) {
        if node.type == "file", node.path.lowercased().hasSuffix(".svg") {
            paths.append(node.path)
        }
        node.files?.forEach { collectSVGPaths(from: $0, into: &paths) }
    }

    // MARK: - GitHub via Git Trees API (recursive, handles any directory structure)

    static func resolveGitHub(
        owner: String,
        repo: String,
        path: String?,
        token: String?,
        progress: @escaping (Int, Int) -> Void
    ) async throws -> [(name: String, content: String)] {
        // 1 — Get the default branch name
        let branch = try await fetchDefaultBranch(owner: owner, repo: repo, token: token)

        // 2 — Get the full recursive file tree in one call
        let allPaths = try await fetchGitTree(owner: owner, repo: repo, branch: branch, token: token)

        // 3 — Filter to .svg files, honouring any subpath the user specified in the URL
        let svgPaths: [String]
        if let path, !path.isEmpty {
            let prefix = path.hasSuffix("/") ? path : path + "/"
            svgPaths = allPaths.filter { $0.hasPrefix(prefix) && $0.lowercased().hasSuffix(".svg") }
        } else {
            svgPaths = allPaths.filter { $0.lowercased().hasSuffix(".svg") }
        }

        guard !svgPaths.isEmpty else { throw ImportError.noSVGsFound }

        // 4 — Download via raw.githubusercontent.com (no auth required, no API rate limits)
        let rawBase = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/"
        let urls: [URL] = svgPaths.compactMap { filePath in
            let encoded = filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath
            return URL(string: rawBase + encoded)
        }

        return try await downloadFiles(urls: urls, progress: progress)
    }

    private static func fetchDefaultBranch(owner: String, repo: String, token: String?) async throws -> String {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else {
            throw ImportError.invalidURL
        }
        let (data, response) = try await githubRequest(url: url, token: token)
        try checkGitHubStatus(response, owner: owner, repo: repo)
        return try JSONDecoder().decode(GitHubRepo.self, from: data).defaultBranch
    }

    private static func fetchGitTree(owner: String, repo: String, branch: String, token: String?) async throws -> [String] {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1") else {
            throw ImportError.invalidURL
        }
        let (data, response) = try await githubRequest(url: url, token: token)
        try checkGitHubStatus(response, owner: owner, repo: repo)
        let tree = try JSONDecoder().decode(GitHubTree.self, from: data)
        return tree.tree.filter { $0.type == "blob" }.map { $0.path }
    }

    // Shared helper: build a GitHub API request with optional Bearer token
    private static func githubRequest(url: URL, token: String?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Sigil/1.0", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await URLSession.shared.data(for: request)
    }

    private static func checkGitHubStatus(_ response: URLResponse, owner: String, repo: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 403: throw ImportError.rateLimited
        case 404: throw ImportError.repositoryNotFound("\(owner)/\(repo)")
        default: break
        }
    }

    // MARK: - ZIP

    static func resolveZIP(
        url: URL,
        progress: @escaping (Int, Int) -> Void
    ) async throws -> [(name: String, content: String)] {
        progress(0, 1)
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sigil-zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        // -j: junk paths (flatten), -o: overwrite without prompting
        process.arguments = ["-j", "-o", tempURL.path, "*.svg", "-d", extractDir.path]
        try process.run()
        process.waitUntilExit()

        let svgFiles = (try? FileManager.default.contentsOfDirectory(
            at: extractDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension.lowercased() == "svg" } ?? []

        guard !svgFiles.isEmpty else { throw ImportError.noSVGsFound }

        let result: [(name: String, content: String)] = svgFiles.compactMap { fileURL in
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
            return (fileURL.deletingPathExtension().lastPathComponent, content)
        }

        progress(1, 1)
        return result
    }

    // MARK: - Shared batch downloader

    private static func downloadFiles(
        urls: [URL],
        progress: @escaping (Int, Int) -> Void
    ) async throws -> [(name: String, content: String)] {
        let total = urls.count
        var results: [(name: String, content: String)] = []
        results.reserveCapacity(total)

        // Concurrency limit: 20 simultaneous downloads
        try await withThrowingTaskGroup(of: (String, String)?.self) { group in
            var inFlight = 0
            var urlIterator = urls.makeIterator()
            var completed = 0

            while inFlight < 20, let url = urlIterator.next() {
                group.addTask { try await downloadSingleSVG(url: url) }
                inFlight += 1
            }

            for try await result in group {
                completed += 1
                progress(completed, total)
                if let r = result { results.append(r) }

                if let url = urlIterator.next() {
                    group.addTask { try await downloadSingleSVG(url: url) }
                }
            }
        }

        return results
    }

    private static func downloadSingleSVG(url: URL) async throws -> (String, String)? {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let content = String(data: data, encoding: .utf8),
              content.contains("<svg") else { return nil }
        return (url.deletingPathExtension().lastPathComponent, content)
    }

    // MARK: - Response models

    struct UnpkgMeta: Decodable {
        let type: String
        let path: String
        let files: [UnpkgMeta]?
    }

    struct GitHubRepo: Decodable {
        let defaultBranch: String
        enum CodingKeys: String, CodingKey {
            case defaultBranch = "default_branch"
        }
    }

    struct GitHubTree: Decodable {
        let tree: [GitHubTreeItem]
    }

    struct GitHubTreeItem: Decodable {
        let path: String
        let type: String  // "blob" = file, "tree" = directory
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case invalidURL
        case noSVGsFound
        case rateLimited
        case packageNotFound(String)
        case repositoryNotFound(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL."
            case .noSVGsFound:
                return "No SVG icons were found at this source."
            case .rateLimited:
                return "GitHub API rate limit reached. Add a GitHub token in Settings to import large packs."
            case .packageNotFound(let p):
                return "npm package \"\(p)\" not found."
            case .repositoryNotFound(let r):
                return "GitHub repository \"\(r)\" not found or is private."
            }
        }
    }
}
