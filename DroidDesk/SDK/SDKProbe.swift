import Foundation

/// Looks for an SDK root, then checks that each required tool can actually run.
struct SDKProbe: Sendable {
    var runner = CommandRunner()

    func inspect() async -> SDKInspection {
        guard let root = SDKLocator.existingRoot() else {
            return SDKInspection(root: nil, tools: AndroidSDKTool.allCases.map { SDKToolStatus(tool: $0, isReady: false) })
        }

        let environment = AndroidCommandEnvironment(sdkRoot: root).values
        let tools = await withTaskGroup(of: SDKToolStatus.self) { group in
            for tool in AndroidSDKTool.allCases {
                group.addTask {
                    await self.status(of: tool, in: root, environment: environment)
                }
            }
            var found: [AndroidSDKTool: SDKToolStatus] = [:]
            for await status in group {
                found[status.tool] = status
            }
            return AndroidSDKTool.allCases.map { found[$0] ?? SDKToolStatus(tool: $0, isReady: false) }
        }
        return SDKInspection(root: root, tools: tools)
    }

    private func status(of tool: AndroidSDKTool, in root: URL, environment: [String: String]) async -> SDKToolStatus {
        let executable = root.appending(path: tool.executableRelativePath)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return SDKToolStatus(tool: tool, isReady: false)
        }
        let ready = await runner.succeeds(
            executable: executable,
            arguments: tool.versionArguments,
            environment: environment
        )
        return SDKToolStatus(tool: tool, isReady: ready)
    }
}

enum SDKLocator {
    static var conventionalRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Android/sdk", directoryHint: .isDirectory)
    }

    /// App-configured path comes later. Until then: `ANDROID_SDK_ROOT`, `ANDROID_HOME`, then the usual Mac location.
    static func existingRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var seen = Set<String>()
        for candidate in candidates(environment: environment) {
            let standardized = candidate.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return standardized
            }
        }
        return nil
    }

    static func candidates(environment: [String: String]) -> [URL] {
        var urls: [URL] = []
        for key in ["ANDROID_SDK_ROOT", "ANDROID_HOME"] {
            if let value = environment[key], !value.isEmpty {
                urls.append(URL(fileURLWithPath: value, isDirectory: true))
            }
        }
        urls.append(conventionalRoot)
        return urls
    }
}

struct AndroidCommandEnvironment: Sendable {
    var sdkRoot: URL

    var values: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let root = sdkRoot.path
        environment["ANDROID_SDK_ROOT"] = root
        environment["ANDROID_HOME"] = root
        let prefix = "\(root)/platform-tools:\(root)/emulator:\(root)/cmdline-tools/latest/bin"
        let path = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = "\(prefix):\(path)"
        return environment
    }
}
