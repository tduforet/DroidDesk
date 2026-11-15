import Foundation

enum ActivityOutcome: String, Codable, Sendable {
    case running
    case succeeded
    case failed
    case declined

    init(_ outcome: SDKInstallOutcome) {
        switch outcome {
        case .updated: self = .succeeded
        case .declined: self = .declined
        case .failed: self = .failed
        }
    }

    var label: String {
        switch self {
        case .running: "Running"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .declined: "Declined"
        }
    }
}

struct ActivityEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var command: String
    var startedAt: Date
    var endedAt: Date?
    var exitCode: Int32?
    var standardOutput: String
    var standardError: String
    var outcome: ActivityOutcome
}

enum ActivityCommand {
    static func line(executable: URL, arguments: [String]) -> String {
        ([executable.lastPathComponent] + arguments).map(quoted).joined(separator: " ")
    }

    private static func quoted(_ word: String) -> String {
        guard word.contains(where: { $0.isWhitespace }) else { return word }
        return "\"\(word.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

/// User-started installs, updates, and emulator commands. Probes such as `--list` and boot checks stay out.
@MainActor
@Observable
final class ActivityLog {
    static let shared = ActivityLog()

    private(set) var entries: [ActivityEntry] = []
    private let limit = 40
    private let outputLimit = 80_000

    private init() {
        entries = Self.load()
        if entries.contains(where: { $0.outcome == .running }) {
            entries = entries.map(Self.settle)
            save()
        }
    }

    @discardableResult
    func begin(title: String, command: String) -> UUID {
        let entry = ActivityEntry(
            id: UUID(),
            title: title,
            command: command,
            startedAt: Date(),
            endedAt: nil,
            exitCode: nil,
            standardOutput: "",
            standardError: "",
            outcome: .running
        )
        entries.insert(entry, at: 0)
        trim()
        save()
        return entry.id
    }

    func finish(
        _ id: UUID,
        exitCode: Int32?,
        standardOutput: String,
        standardError: String,
        outcome: ActivityOutcome
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].endedAt = Date()
        entries[index].exitCode = exitCode
        entries[index].standardOutput = clip(standardOutput)
        entries[index].standardError = clip(standardError)
        entries[index].outcome = outcome
        save()
    }

    func report() -> String {
        var lines = ["DroidDesk"]
        if let root = SDKLocator.existingRoot() {
            lines.append("SDK: \(SDKPathDisplay.tilde(root))")
            for tool in AndroidSDKTool.allCases {
                guard let revision = InstalledRevision.read(root: root, tool: tool) else { continue }
                lines.append("\(tool.displayName) \(revision)")
            }
        } else {
            lines.append("SDK: not installed")
        }
        lines.append("")
        if entries.isEmpty {
            lines.append("No commands.")
            return lines.joined(separator: "\n")
        }
        lines.append(entries.map(Self.reportEntry).joined(separator: "\n\n"))
        return lines.joined(separator: "\n")
    }

    private func trim() {
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
    }

    private func clip(_ text: String) -> String {
        guard text.count > outputLimit else { return text }
        return "…\n" + String(text.suffix(outputLimit))
    }

    private static func settle(_ entry: ActivityEntry) -> ActivityEntry {
        guard entry.outcome == .running else { return entry }
        var entry = entry
        entry.outcome = .failed
        entry.endedAt = entry.endedAt ?? Date()
        if entry.standardError.isEmpty {
            entry.standardError = "The command did not finish."
        }
        return entry
    }

    private static func reportEntry(_ entry: ActivityEntry) -> String {
        let started = entry.startedAt.formatted(date: .abbreviated, time: .standard)
        let ended = entry.endedAt?.formatted(date: .abbreviated, time: .standard) ?? "—"
        let exit = entry.exitCode.map(String.init) ?? "—"
        var lines = [
            entry.title,
            "Started: \(started)",
            "Ended: \(ended)",
            "Status: \(entry.outcome.label)",
            "Exit: \(exit)",
            "Command: \(entry.command)",
        ]
        if !entry.standardOutput.isEmpty {
            lines.append("")
            lines.append("Output:")
            lines.append(entry.standardOutput)
        }
        if !entry.standardError.isEmpty {
            lines.append("")
            lines.append("Error:")
            lines.append(entry.standardError)
        }
        return lines.joined(separator: "\n")
    }

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/DroidDesk/activity.json")
    }

    private static func load() -> [ActivityEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ActivityEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
