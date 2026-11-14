import Foundation

/// `sdkmanager --install cmdline-tools;latest` will not replace a `latest` folder that belongs to an older package id.
/// It leaves the new tools in a sibling directory such as `latest-2`.
enum CommandLineToolsLayout {
    static func newestRevision(in sdkRoot: URL, newerThan installed: String) -> String? {
        guard let directory = newestDirectory(in: sdkRoot, newerThan: installed) else { return nil }
        return InstalledRevision.read(directory: directory)
    }

    /// Moves the newest sibling into `cmdline-tools/latest` and keeps the previous tools under their package version.
    static func promoteNewest(in sdkRoot: URL) throws -> Bool {
        let fileManager = FileManager.default
        let root = sdkRoot.appending(path: "cmdline-tools", directoryHint: .isDirectory)
        let latest = root.appending(path: "latest", directoryHint: .isDirectory)
        guard let current = InstalledRevision.read(directory: latest) else { return false }
        guard let best = newestDirectory(in: sdkRoot, newerThan: current) else { return false }

        let parked = availableDirectory(in: root, preferred: parkedName(for: latest))
        try fileManager.moveItem(at: latest, to: parked)
        do {
            try fileManager.moveItem(at: best, to: latest)
        } catch {
            try? fileManager.moveItem(at: parked, to: latest)
            throw error
        }
        return true
    }

    private static func newestDirectory(in sdkRoot: URL, newerThan installed: String) -> URL? {
        let fileManager = FileManager.default
        let root = sdkRoot.appending(path: "cmdline-tools", directoryHint: .isDirectory)
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var best: (url: URL, revision: String)?
        for url in children {
            guard url.lastPathComponent != "latest" else { continue }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let executable = url.appending(path: "bin/sdkmanager")
            guard fileManager.isExecutableFile(atPath: executable.path) else { continue }
            guard let revision = InstalledRevision.read(directory: url),
                  VersionOrdering.isOlder(installed, than: revision) else { continue }
            if best == nil || VersionOrdering.isOlder(best?.revision ?? installed, than: revision) {
                best = (url, revision)
            }
        }
        return best?.url
    }

    private static func parkedName(for directory: URL) -> String {
        let file = directory.appending(path: "source.properties")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "previous" }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "Pkg.Path" else { continue }
            let name = parts[1].trimmingCharacters(in: .whitespaces).split(separator: ";").last.map(String.init) ?? ""
            if name.isEmpty || name == "latest" { return "previous" }
            return name
        }
        return "previous"
    }

    private static func availableDirectory(in root: URL, preferred: String) -> URL {
        let fileManager = FileManager.default
        var candidate = root.appending(path: preferred, directoryHint: .isDirectory)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = root.appending(path: "\(preferred)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        return candidate
    }
}
