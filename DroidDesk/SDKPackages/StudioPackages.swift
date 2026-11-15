import Foundation

/// A platform or build-tools package offered for download, or one already on disk.
struct StudioPackage: Identifiable, Equatable, Sendable {
    var kind: Kind
    var version: String
    var installIdentifier: String
    var relativeDirectory: String

    var id: String { installIdentifier }
    var title: String { kind.title }

    enum Kind: String, Sendable {
        case platform
        case buildTools

        var title: String {
            switch self {
            case .platform: "Android platform"
            case .buildTools: "Build-tools"
            }
        }
    }
}

struct StudioPackageStatus: Identifiable, Equatable, Sendable {
    var package: StudioPackage
    var isInstalled: Bool

    var id: String { package.id }
}

enum StudioPackageCatalogue {
    /// Stable platforms from API 36 upward, newest first. Extensions, betas, and canaries are left out.
    static func offeredPlatforms(in listOutput: String) -> [StudioPackage] {
        candidates(in: listOutput)
            .filter { $0.kind == .platform && AndroidAPIFloor.includes($0.version) }
            .sorted { VersionOrdering.isOlder($1.version, than: $0.version) }
    }

    /// Stable build-tools from API 36 upward, newest first. Release candidates are left out.
    static func offeredBuildTools(in listOutput: String) -> [StudioPackage] {
        candidates(in: listOutput)
            .filter { $0.kind == .buildTools && AndroidAPIFloor.includes($0.version) }
            .sorted { VersionOrdering.isOlder($1.version, than: $0.version) }
    }

    static func candidates(in listOutput: String) -> [StudioPackage] {
        var byIdentifier: [String: StudioPackage] = [:]
        for rawLine in listOutput.split(whereSeparator: \.isNewline) {
            guard let identifier = rawLine.trimmingCharacters(in: .whitespaces).split(separator: "|").first
                .map({ $0.trimmingCharacters(in: .whitespaces) }),
                  let package = package(identifier: identifier) else { continue }
            byIdentifier[package.installIdentifier] = package
        }
        return Array(byIdentifier.values)
    }

    private static func package(identifier: String) -> StudioPackage? {
        let normalized = identifier.replacingOccurrences(of: "/", with: ";")
        let platformPattern = /platforms;android-(\d+(?:\.\d+)?)/
        let buildToolsPattern = /build-tools;(\d+\.\d+\.\d+)/
        if let version = normalized.wholeMatch(of: platformPattern)?.1 {
            let value = String(version)
            return StudioPackage(
                kind: .platform,
                version: value,
                installIdentifier: "platforms;android-\(value)",
                relativeDirectory: "platforms/android-\(value)"
            )
        }
        if let version = normalized.wholeMatch(of: buildToolsPattern)?.1 {
            let value = String(version)
            return StudioPackage(
                kind: .buildTools,
                version: value,
                installIdentifier: "build-tools;\(value)",
                relativeDirectory: "build-tools/\(value)"
            )
        }
        return nil
    }
}

enum StudioPackageDisk {
    static func installed(in root: URL) -> [StudioPackage] {
        installedPlatforms(in: root) + installedBuildTools(in: root)
    }

    static func isInstalled(_ package: StudioPackage, in root: URL) -> Bool {
        let directory = root.appending(path: package.relativeDirectory, directoryHint: .isDirectory)
        return InstalledRevision.read(directory: directory) != nil
    }

    private static func installedPlatforms(in root: URL) -> [StudioPackage] {
        directories(in: root.appending(path: "platforms", directoryHint: .isDirectory)).compactMap { directory in
            let name = directory.lastPathComponent
            guard name.hasPrefix("android-"), !name.contains("-ext") else { return nil }
            let version = String(name.dropFirst("android-".count))
            guard version.wholeMatch(of: /^\d+(?:\.\d+)?$/) != nil else { return nil }
            guard InstalledRevision.read(directory: directory) != nil else { return nil }
            return StudioPackage(
                kind: .platform,
                version: version,
                installIdentifier: "platforms;android-\(version)",
                relativeDirectory: "platforms/android-\(version)"
            )
        }
    }

    private static func installedBuildTools(in root: URL) -> [StudioPackage] {
        directories(in: root.appending(path: "build-tools", directoryHint: .isDirectory)).compactMap { directory in
            let version = directory.lastPathComponent
            guard version.wholeMatch(of: /^\d+\.\d+\.\d+$/) != nil else { return nil }
            guard InstalledRevision.read(directory: directory) != nil else { return nil }
            return StudioPackage(
                kind: .buildTools,
                version: version,
                installIdentifier: "build-tools;\(version)",
                relativeDirectory: "build-tools/\(version)"
            )
        }
    }

    private static func directories(in folder: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}
