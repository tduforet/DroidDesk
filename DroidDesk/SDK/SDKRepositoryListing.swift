import Foundation

/// What `sdkmanager --list --newer` says about the packages behind the four tools.
struct SDKRepositoryListing: Equatable, Sendable {
    /// Package id to the newer version, from the Available Updates table.
    var updates: [String: String]
    /// Version of `cmdline-tools;latest` in Available Packages.
    var latestCommandLineTools: String?

    func availableVersion(for tool: AndroidSDKTool, installed: String?) -> String? {
        switch tool.package {
        case .platformTools:
            return updates["platform-tools"]
        case .emulator:
            return updates["emulator"]
        case .commandLineTools:
            if let listed = updates["cmdline-tools"] ?? updates["cmdline-tools;latest"] {
                return listed
            }
            // Installed bits can be recorded as `cmdline-tools;19.0` while the
            // current release is published as `cmdline-tools;latest`.
            guard let installed, let latest = latestCommandLineTools, VersionOrdering.isOlder(installed, than: latest) else {
                return nil
            }
            return latest
        }
    }
}

enum AndroidSDKPackage: Sendable {
    case commandLineTools
    case platformTools
    case emulator

    /// Identifier `sdkmanager --install` expects for this package.
    var installIdentifier: String {
        switch self {
        case .commandLineTools: "cmdline-tools;latest"
        case .platformTools: "platform-tools"
        case .emulator: "emulator"
        }
    }
}

extension AndroidSDKTool {
    var package: AndroidSDKPackage {
        switch self {
        case .sdkmanager, .avdmanager: .commandLineTools
        case .adb: .platformTools
        case .emulator: .emulator
        }
    }

    var revisionPropertiesPath: String {
        switch package {
        case .commandLineTools: "cmdline-tools/latest/source.properties"
        case .platformTools: "platform-tools/source.properties"
        case .emulator: "emulator/source.properties"
        }
    }
}

enum SDKRepositoryListingParser {
    static func parse(_ output: String) -> SDKRepositoryListing {
        var section = Section.other
        var updates: [String: String] = [:]
        var latestCommandLineTools: String?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let header = line.lowercased()
            if header.hasPrefix("available updates") {
                section = .updates
                continue
            }
            if header.hasPrefix("available packages") {
                section = .available
                continue
            }
            if header.hasPrefix("installed packages") {
                section = .installed
                continue
            }

            let columns = line.contains("|") ? pipeColumns(line) : wideColumns(line)
            guard let identifier = columns.first.map(normalize), !identifier.isEmpty,
                  identifier != "Path", identifier != "ID", !identifier.hasPrefix("-") else { continue }

            switch section {
            case .updates:
                guard columns.count >= 3 else { continue }
                let available = columns[2]
                guard !available.isEmpty, !available.hasPrefix("-") else { continue }
                updates[identifier] = available
            case .installed:
                guard let arrow = columns.firstIndex(of: "->"), arrow + 1 < columns.count else { continue }
                let available = columns[arrow + 1]
                guard !available.isEmpty, available != "unknown", !available.hasPrefix("-") else { continue }
                updates[identifier] = available
            case .available:
                guard columns.count >= 2 else { continue }
                let version = columns[1]
                guard !version.isEmpty, version != "Version" else { continue }
                if identifier == "cmdline-tools;latest" {
                    latestCommandLineTools = version
                }
            case .other:
                break
            }
        }

        return SDKRepositoryListing(updates: updates, latestCommandLineTools: latestCommandLineTools)
    }

    /// Older sdkmanager prints `cmdline-tools;latest`. Version 23 prints `cmdline-tools/latest`.
    private static func normalize(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "/", with: ";")
    }

    private static func pipeColumns(_ line: String) -> [String] {
        line.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Version 23 separates columns with two or more spaces, and marks an update as `37.1.11 -> 37.2.13`.
    private static func wideColumns(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var spaceRun = 0
        func finishColumn() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { columns.append(trimmed) }
            current = ""
        }
        for character in line {
            if character == " " || character == "\t" {
                spaceRun += 1
                continue
            }
            if spaceRun >= 2 {
                finishColumn()
            } else if spaceRun == 1 {
                current.append(" ")
            }
            spaceRun = 0
            current.append(character)
        }
        finishColumn()
        return columns
    }

    private enum Section {
        case other
        case installed
        case available
        case updates
    }
}

enum VersionOrdering {
    static func isOlder(_ installed: String, than available: String) -> Bool {
        let left = components(installed)
        let right = components(available)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs < rhs }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        let numeric = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        return numeric.split(separator: ".").compactMap { Int($0) }
    }
}

enum InstalledRevision {
    static func read(root: URL, tool: AndroidSDKTool) -> String? {
        read(file: root.appending(path: tool.revisionPropertiesPath))
    }

    static func read(directory: URL) -> String? {
        read(file: directory.appending(path: "source.properties"))
    }

    private static func read(file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "Pkg.Revision" else { continue }
            let revision = parts[1].trimmingCharacters(in: .whitespaces)
            return revision.isEmpty ? nil : revision
        }
        return nil
    }
}
