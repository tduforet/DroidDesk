import Foundation

/// The four tools the Dashboard reports. Managers come first, then the tools they install.
enum AndroidSDKTool: String, CaseIterable, Identifiable, Sendable {
    case sdkmanager
    case avdmanager
    case adb
    case emulator

    var id: String { rawValue }
    var displayName: String { rawValue }

    var executableRelativePath: String {
        switch self {
        case .sdkmanager: "cmdline-tools/latest/bin/sdkmanager"
        case .adb: "platform-tools/adb"
        case .emulator: "emulator/emulator"
        case .avdmanager: "cmdline-tools/latest/bin/avdmanager"
        }
    }

    var versionArguments: [String] {
        switch self {
        case .sdkmanager: ["--version"]
        case .adb: ["version"]
        case .emulator: ["-version"]
        case .avdmanager: ["list", "target"]
        }
    }
}

struct SDKToolStatus: Identifiable, Equatable, Sendable {
    var tool: AndroidSDKTool
    var isReady: Bool
    /// Package revision from the SDK, such as `37.0.1`. Absent when the tool cannot run.
    var installedVersion: String?
    /// Newer revision published by Google. Absent when nothing newer is listed, or the catalogue could not be read.
    var availableVersion: String?

    var id: AndroidSDKTool { tool }
    var statusLabel: String { isReady ? "Ready" : "Missing" }
}

struct SDKInspection: Equatable, Sendable {
    var root: URL?
    var tools: [SDKToolStatus]

    var title: String {
        guard root != nil else { return "No Android SDK found" }
        let missing = tools.filter { !$0.isReady }.map(\.tool.displayName)
        switch missing.count {
        case 0: return "SDK ready"
        case 1: return "\(missing[0]) is missing"
        default: return "\(missing.count) tools are missing"
        }
    }

    var pathLine: String {
        SDKPathDisplay.tilde(root ?? SDKLocator.conventionalRoot)
    }
}

enum SDKPathDisplay {
    static func tilde(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
