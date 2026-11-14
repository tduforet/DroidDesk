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

enum SDKPathRules {
    static func isUnderHome(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path != home && path.hasPrefix(home + "/")
    }

    static func isProtected(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath()
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

    static func accepted(_ url: URL) -> URL? {
        let presented = url.standardizedFileURL
        let resolved = presented.resolvingSymlinksInPath()
        guard SDKPathRules.isUnderHome(presented), SDKPathRules.isUnderHome(resolved) else { return nil }
        guard !SDKPathRules.isProtected(presented), !SDKPathRules.isProtected(resolved) else { return nil }
        if FileManager.default.fileExists(atPath: presented.path) {
            let values = try? presented.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values?.isSymbolicLink != true, values?.isDirectory == true else { return nil }
        }
        return presented
    }
}

enum SDKFolderPicker {
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
