import Foundation

/// Deletes one SDK folder after checking it is a real Android SDK under the user's home.
enum SDKRemover {
    enum Outcome: Sendable {
        case removed
        case failed(String)
    }

    static func remove(_ root: URL) async -> Outcome {
        await Task.detached(priority: .userInitiated) {
            do {
                try perform(root)
                return .removed
            } catch let failure as RemovalFailure {
                return .failed(failure.message)
            } catch let cocoa as CocoaError where cocoa.code == .fileReadNoSuchFile || cocoa.code == .fileNoSuchFile {
                return .failed("The SDK folder is already gone.")
            } catch {
                return .failed("The SDK folder could not be removed.")
            }
        }.value
    }

    private static func perform(_ root: URL) throws {
        let target = try validatedTarget(root)
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
    private static func validatedTarget(_ root: URL) throws -> URL {
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
        guard SDKPathRules.isUnderHome(presented), SDKPathRules.isUnderHome(resolved) else {
            throw RemovalFailure(message: refusedMessage)
        }
        guard !SDKPathRules.isProtected(presented), !SDKPathRules.isProtected(resolved) else {
            throw RemovalFailure(message: refusedMessage)
        }
        let conventional = SDKLocator.conventionalRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let configured = SDKLocationStore.url?.resolvingSymlinksInPath().path
        if resolved.path == conventional || resolved.path == configured {
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
