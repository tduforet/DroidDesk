import CryptoKit
import Foundation

/// The official command-line tools archive for this Mac. The checksum is the published build, so a newer sdkmanager can still be installed later with Update.
enum CommandLineToolsArchive {
    struct Package: Sendable {
        var url: URL
        var sha256: String
    }

    static var host: Package {
        #if arch(arm64)
        Package(
            url: URL(string: "https://dl.google.com/android/repository/commandlinetools-mac_arm64-15859902_latest.zip")!,
            sha256: "835b62a26162b229b441d1f6d4680383815a270809eb33522c0d480fa5002c4e"
        )
        #else
        Package(
            url: URL(string: "https://dl.google.com/android/repository/commandlinetools-mac_x86_64-15859902_latest.zip")!,
            sha256: "c5a6378ab5cf7e0d5701921405115befff13e9ff7417fb588389338f8bd050f3"
        )
        #endif
    }
}

/// Downloads command-line tools and places them at `cmdline-tools/latest`, which is where `sdkmanager` has to live.
struct CommandLineToolsBootstrap: Sendable {
    var archive = CommandLineToolsArchive.host
    var runner = CommandRunner()

    func install(into sdkRoot: URL) async -> SDKInstallOutcome {
        let id = await ActivityLog.shared.begin(
            title: "Download command-line tools",
            command: archive.url.absoluteString
        )
        let outcome = await place(into: sdkRoot)
        let exit: Int32? = if case .updated = outcome { 0 } else { 1 }
        let detail = if case .failed(let message) = outcome { message } else { "" }
        await ActivityLog.shared.finish(
            id,
            exitCode: exit,
            standardOutput: "",
            standardError: detail,
            outcome: ActivityOutcome(outcome)
        )
        return outcome
    }

    private func place(into sdkRoot: URL) async -> SDKInstallOutcome {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appending(path: "droiddesk-cmdline-tools-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            return .failed("The command-line tools could not be downloaded.")
        }
        defer { try? fileManager.removeItem(at: work) }

        let zip = work.appending(path: "commandlinetools.zip")
        do {
            try await download(archive.url, to: zip)
        } catch {
            return .failed("The command-line tools could not be downloaded.")
        }

        guard let digest = try? FileDigest.sha256(of: zip), digest == archive.sha256.lowercased() else {
            return .failed("The command-line tools download did not match the expected checksum.")
        }

        let extracted = work.appending(path: "extracted", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        } catch {
            return .failed("The command-line tools archive could not be unpacked.")
        }
        let unpacked = await runner.succeeds(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-xk", zip.path, extracted.path],
            environment: ProcessInfo.processInfo.environment,
            timeout: .seconds(120)
        )
        let payload = extracted.appending(path: "cmdline-tools", directoryHint: .isDirectory)
        let sdkmanager = payload.appending(path: "bin/sdkmanager")
        guard unpacked, fileManager.fileExists(atPath: sdkmanager.path) else {
            return .failed("The command-line tools archive could not be unpacked.")
        }

        let destinationParent = sdkRoot.appending(path: "cmdline-tools", directoryHint: .isDirectory)
        let latest = destinationParent.appending(path: "latest", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: latest.path) {
                let backup = destinationParent.appending(path: "previous", directoryHint: .isDirectory)
                if fileManager.fileExists(atPath: backup.path) {
                    try fileManager.removeItem(at: backup)
                }
                try fileManager.moveItem(at: latest, to: backup)
            }
            try fileManager.moveItem(at: payload, to: latest)
        } catch {
            return .failed("The command-line tools could not be moved into place.")
        }
        makeToolsExecutable(in: latest.appending(path: "bin", directoryHint: .isDirectory))
        return .updated
    }

    private func download(_ url: URL, to destination: URL) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 900
        let session = URLSession(configuration: configuration)
        let (temporary, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private func makeToolsExecutable(in bin: URL) {
        let fileManager = FileManager.default
        guard let tools = try? fileManager.contentsOfDirectory(at: bin, includingPropertiesForKeys: nil) else { return }
        for tool in tools {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        }
    }
}

enum FileDigest {
    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
