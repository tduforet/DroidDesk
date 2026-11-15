import Foundation

/// Deletes one SDK folder after checking it is a real Android SDK under the user's home.
enum SDKRemover {
    enum Outcome: Sendable {
        case removed
        case failed(String)
    }

    static func remove(_ root: URL) async -> Outcome {
        let id = await ActivityLog.shared.begin(
            title: "Remove SDK",
            command: SDKPathDisplay.tilde(root)
        )
        let configured = SDKLocationStore.url
        let outcome = await Task.detached(priority: .userInitiated) {
            removeNow(root, configured: configured)
        }.value
        switch outcome {
        case .removed:
            await ActivityLog.shared.finish(
                id,
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                outcome: .succeeded
            )
        case .failed(let message):
            await ActivityLog.shared.finish(
                id,
                exitCode: 1,
                standardOutput: "",
                standardError: message,
                outcome: .failed
            )
        }
        return outcome
    }

    /// Validates and deletes `root`. `home` and `configured` are parameters so tests never touch the real ones.
    static func removeNow(
        _ root: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        configured: URL? = SDKLocationStore.url
    ) -> Outcome {
        do {
            try perform(root, home: home, configured: configured)
            return .removed
        } catch let failure as RemovalFailure {
            return .failed(failure.message)
        } catch let cocoa as CocoaError where cocoa.code == .fileReadNoSuchFile || cocoa.code == .fileNoSuchFile {
            return .failed("The SDK folder is already gone.")
        } catch {
            return .failed("The SDK folder could not be removed.")
        }
    }

    private static func perform(_ root: URL, home: URL, configured: URL?) throws {
        let target = try validatedTarget(root, home: home, configured: configured)
        let holding = target.deletingLastPathComponent()
            .appending(path: ".\(target.lastPathComponent)-removing-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.moveItem(at: target, to: holding)
        } catch {
            throw RemovalFailure(message: "The SDK folder could not be removed.")
        }
        do {
            try FileManager.default.removeItem(at: holding)
        } catch {
            if !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.moveItem(at: holding, to: target)
            }
            if FileManager.default.fileExists(atPath: holding.path) {
                throw RemovalFailure(
                    message: "The SDK folder could not be removed. A copy is still at \(SDKPathDisplay.tilde(holding))."
                )
            }
            throw RemovalFailure(message: "The SDK folder could not be removed.")
        }
    }

    /// The folder DroidDesk is allowed to delete: the usual SDK path, or another SDK root that already contains SDK packages.
    private static func validatedTarget(_ root: URL, home: URL, configured: URL?) throws -> URL {
        let presented = root.standardizedFileURL
        guard presented.path != "/", presented.path != "/Users" else {
            throw RemovalFailure(message: refusedMessage)
        }
        let values = try presented.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true else {
            throw RemovalFailure(message: "The SDK path is a shortcut, so it was left in place.")
        }
        guard values.isDirectory == true else {
            throw RemovalFailure(message: "The SDK folder is already gone.")
        }

        let resolved = presented.resolvingSymlinksInPath()
        guard SDKPathRules.isUnderHome(presented, home: home), SDKPathRules.isUnderHome(resolved, home: home) else {
            throw RemovalFailure(message: refusedMessage)
        }
        guard !SDKPathRules.isProtected(presented, home: home), !SDKPathRules.isProtected(resolved, home: home) else {
            throw RemovalFailure(message: refusedMessage)
        }
        let conventional = SDKLocator.conventionalRoot(home: home).standardizedFileURL.resolvingSymlinksInPath().path
        let configuredPath = configured?.resolvingSymlinksInPath().path
        if resolved.path == conventional || resolved.path == configuredPath {
            return presented
        }
        guard SDKPathRules.containsSDKMarker(resolved) else {
            throw RemovalFailure(message: refusedMessage)
        }
        return presented
    }

    private static let refusedMessage = "That folder is not an Android SDK, so it was left in place."
}

private struct RemovalFailure: Error {
    var message: String
}
