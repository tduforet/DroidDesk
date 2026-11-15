import AppKit
import Foundation

/// Where a new SDK may be installed. The usual Mac location is the default until the user chooses another folder.
enum SDKLocationStore {
    private static let key = "configuredSDKRoot"

    static var url: URL? {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func save(_ url: URL) {
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Where a folder setting comes from, strongest first.
enum PathSource: Equatable, Sendable {
    case app
    case environment(String)
    case standard

    var label: String {
        switch self {
        case .app: "Chosen in DroidDesk"
        case .environment(let name): "From \(name)"
        case .standard: "Default location"
        }
    }
}

enum SDKPathRules {
    static func isUnderHome(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let home = home.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path != home && path.hasPrefix(home + "/")
    }

    static func isProtected(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let home = home.standardizedFileURL.resolvingSymlinksInPath()
        let protected = [
            "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public", "Applications", "Library",
            "Library/Android", ".android",
        ].map { home.appending(path: $0).standardizedFileURL.resolvingSymlinksInPath().path }
        return protected.contains(url.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    static func containsSDKMarker(_ url: URL) -> Bool {
        let markers = ["cmdline-tools", "platform-tools", "emulator", "platforms", "build-tools", "system-images", "licenses"]
        return markers.contains { FileManager.default.fileExists(atPath: url.appending(path: $0).path) }
    }
}

/// A folder the user may pick for sdkmanager and avdmanager. It has to live in their home, and not be a home folder itself.
enum SDKInstallLocation {
    static let rejectionMessage = "Choose a folder inside your home directory."

    static func accepted(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let presented = url.standardizedFileURL
        let resolved = presented.resolvingSymlinksInPath()
        guard SDKPathRules.isUnderHome(presented, home: home), SDKPathRules.isUnderHome(resolved, home: home) else { return nil }
        guard !SDKPathRules.isProtected(presented, home: home), !SDKPathRules.isProtected(resolved, home: home) else { return nil }
        if FileManager.default.fileExists(atPath: presented.path) {
            let values = try? presented.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values?.isSymbolicLink != true, values?.isDirectory == true else { return nil }
        }
        return presented
    }
}

/// Whether DroidDesk may use a folder as the SDK root. Using a folder never moves or deletes anything in it.
enum SDKFolderRules {
    enum Verdict: Equatable, Sendable {
        /// Inside the home folder. It may be empty: the SDK can be installed there.
        case install
        /// Outside the home folder, and already an Android SDK. DroidDesk uses it and leaves it in place.
        case existing
        case rejected(String)
    }

    static let rejection = "Choose a folder inside your home directory, or an existing Android SDK."

    static func verdict(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Verdict {
        let presented = url.standardizedFileURL
        let resolved = presented.resolvingSymlinksInPath()
        let homePath = home.standardizedFileURL.resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: presented.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            return .rejected("That is a file, not a folder.")
        }
        guard presented.path != homePath, resolved.path != homePath, resolved.path != "/" else {
            return .rejected(rejection)
        }
        guard !SDKPathRules.isProtected(presented, home: home), !SDKPathRules.isProtected(resolved, home: home) else {
            return .rejected(rejection)
        }
        if SDKInstallLocation.accepted(presented, home: home) != nil { return .install }
        if SDKPathRules.isUnderHome(presented, home: home) || SDKPathRules.isUnderHome(resolved, home: home) {
            return .rejected(rejection)
        }
        return SDKPathRules.containsSDKMarker(resolved) ? .existing : .rejected(rejection)
    }
}

enum SDKFolderPicker {
    /// A plain folder chooser. The caller decides whether the folder is acceptable.
    @MainActor
    static func pick(message: String, startingAt url: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        if let url { panel.directoryURL = existingAncestor(of: url) }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    enum Result {
        case cancelled
        case rejected
        case selected(URL)
    }

    @MainActor
    static func choose(startingAt url: URL) -> Result {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder where sdkmanager and avdmanager will be installed."
        panel.directoryURL = existingAncestor(of: url.deletingLastPathComponent())
        guard panel.runModal() == .OK, let picked = panel.url else { return .cancelled }
        guard let accepted = SDKInstallLocation.accepted(picked) else { return .rejected }
        return .selected(accepted)
    }

    private static func existingAncestor(of url: URL) -> URL {
        var current = url.standardizedFileURL
        let fileManager = FileManager.default
        while current.path != "/" {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: current.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return current
            }
            current.deleteLastPathComponent()
        }
        return fileManager.homeDirectoryForCurrentUser
    }
}
