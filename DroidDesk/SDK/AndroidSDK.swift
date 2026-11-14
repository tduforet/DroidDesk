import Foundation

/// The four tools the Dashboard reports. Order is the order shown in the list.
enum AndroidSDKTool: String, CaseIterable, Identifiable, Sendable {
    case sdkmanager
    case adb
    case emulator
    case avdmanager

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
