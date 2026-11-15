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
        let listing = await repositoryListing(in: root, environment: environment, tools: tools)
        let annotated = tools.map { status in
            var status = status
            guard status.isReady else { return status }
            let listed = listing.availableVersion(for: status.tool, installed: status.installedVersion)
            let sibling = commandLineToolsSibling(of: status, in: root)
            status.availableVersion = newerVersion(listed, sibling)
            return status
        }
        return SDKInspection(root: root, tools: annotated)
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
        return SDKToolStatus(
            tool: tool,
            isReady: ready,
            installedVersion: ready ? InstalledRevision.read(root: root, tool: tool) : nil
        )
    }

    /// `sdkmanager` sometimes leaves a newer command-line tools package beside `latest` instead of replacing it.
    private func commandLineToolsSibling(of status: SDKToolStatus, in root: URL) -> String? {
        guard status.tool.package == .commandLineTools, let installed = status.installedVersion else { return nil }
        return CommandLineToolsLayout.newestRevision(in: root, newerThan: installed)
    }

    private func newerVersion(_ listed: String?, _ sibling: String?) -> String? {
        switch (listed, sibling) {
        case let (listed?, sibling?):
            return VersionOrdering.isOlder(listed, than: sibling) ? sibling : listed
        case (let listed?, nil):
            return listed
        case (nil, let sibling?):
            return sibling
        case (nil, nil):
            return nil
        }
    }

    private func repositoryListing(in root: URL, environment: [String: String], tools: [SDKToolStatus]) async -> SDKRepositoryListing {
        guard tools.contains(where: { $0.tool == .sdkmanager && $0.isReady }) else {
            return SDKRepositoryListing(updates: [:], latestCommandLineTools: nil)
        }
        let executable = root.appending(path: AndroidSDKTool.sdkmanager.executableRelativePath)
        guard let result = await runner.run(
            executable: executable,
            arguments: ["--list", "--newer"],
            environment: environment,
            timeout: .seconds(30)
        ), result.exitCode == 0 else {
            return SDKRepositoryListing(updates: [:], latestCommandLineTools: nil)
        }
        return SDKRepositoryListingParser.parse(result.standardOutput)
    }
}

enum SDKLocator {
    static var conventionalRoot: URL {
        conventionalRoot(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    static func conventionalRoot(home: URL) -> URL {
        home.appending(path: "Library/Android/sdk", directoryHint: .isDirectory)
    }

    /// The folder chosen in the app, then `ANDROID_SDK_ROOT`, `ANDROID_HOME`, then the usual Mac location.
    static func existingRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configured: URL? = SDKLocationStore.url,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        var seen = Set<String>()
        for candidate in candidates(environment: environment, configured: configured, home: home) {
            let standardized = candidate.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return standardized
            }
        }
        return nil
    }

    static func candidates(
        environment: [String: String],
        configured: URL? = SDKLocationStore.url,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var urls: [URL] = []
        if let configured {
            urls.append(configured)
        }
        for key in ["ANDROID_SDK_ROOT", "ANDROID_HOME"] {
            if let value = environment[key], !value.isEmpty {
                urls.append(URL(fileURLWithPath: value, isDirectory: true))
            }
        }
        urls.append(conventionalRoot(home: home))
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
