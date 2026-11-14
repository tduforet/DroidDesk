import Foundation
import Synchronization

enum SDKInstallOutcome: Sendable {
    case updated
    case declined
    case failed(String)
}

struct SDKLicensePrompt: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var text: String
}

/// Installs one SDK package with `sdkmanager --install`. A license is answered only after `onLicense` returns.
struct SDKInstaller: Sendable {
    func install(
        package: AndroidSDKPackage,
        availableVersion: String,
        sdkRoot: URL,
        environment: [String: String],
        onLicense: @escaping @MainActor (SDKLicensePrompt) async -> Bool
    ) async -> SDKInstallOutcome {
        if let settled = promoteCommandLineTools(package, sdkRoot: sdkRoot, availableVersion: availableVersion) {
            return settled
        }
        let outcome = await run(
            packageID: package.installIdentifier,
            sdkRoot: sdkRoot,
            environment: environment,
            onLicense: onLicense
        )
        guard case .updated = outcome else { return outcome }
        if let settled = promoteCommandLineTools(package, sdkRoot: sdkRoot, availableVersion: availableVersion) {
            return settled
        }
        if revisionIsOlder(package, than: availableVersion, sdkRoot: sdkRoot) {
            return .failed("The package could not be updated.")
        }
        return .updated
    }

    /// Moves a newer command-line tools directory into `latest` when one is already on disk.
    /// Returns nil when `sdkmanager` still has to download the package.
    private func promoteCommandLineTools(
        _ package: AndroidSDKPackage,
        sdkRoot: URL,
        availableVersion: String
    ) -> SDKInstallOutcome? {
        guard package == .commandLineTools else { return nil }
        do {
            _ = try CommandLineToolsLayout.promoteNewest(in: sdkRoot)
        } catch {
            return .failed("The command-line tools could not be moved into place.")
        }
        if revisionIsOlder(package, than: availableVersion, sdkRoot: sdkRoot) { return nil }
        return .updated
    }

    private func revisionIsOlder(_ package: AndroidSDKPackage, than available: String, sdkRoot: URL) -> Bool {
        let tool: AndroidSDKTool = switch package {
        case .commandLineTools: .sdkmanager
        case .platformTools: .adb
        case .emulator: .emulator
        }
        guard let installed = InstalledRevision.read(root: sdkRoot, tool: tool) else { return true }
        return VersionOrdering.isOlder(installed, than: available)
    }

    private func run(
        packageID: String,
        sdkRoot: URL,
        environment: [String: String],
        onLicense: @escaping @MainActor (SDKLicensePrompt) async -> Bool
    ) async -> SDKInstallOutcome {
        let process = Process()
        let executable = sdkRoot.appending(path: AndroidSDKTool.sdkmanager.executableRelativePath)
        process.executableURL = executable
        process.arguments = ["--sdk_root=\(sdkRoot.path)", "--install", packageID]
        process.environment = environment

        let pipe = Pipe()
        let input = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = input
        let reader = InstallOutput(pipe.fileHandleForReading)
        let stdin = StandardInput(input.fileHandleForWriting)
        let exit = ExitBox()
        let timedOut = Mutex(false)

        process.terminationHandler = { process in
            reader.finish()
            let status = process.terminationStatus
            Task { await exit.finish(status) }
        }

        do {
            try process.run()
        } catch {
            reader.finish()
            stdin.close()
            return .failed("The update could not start.")
        }

        let watchdog = Task {
            try? await Task.sleep(for: .seconds(1200))
            if process.isRunning {
                timedOut.withLock { $0 = true }
                process.terminate()
            }
        }
        defer {
            watchdog.cancel()
            stdin.close()
        }

        var output = ""
        var seen = 0
        var handled = 0
        var declined = false

        while let data = await reader.wait(after: seen) {
            seen = data.count
            output = String(decoding: data, as: UTF8.self)
            while let pending = SDKLicensePromptParser.next(in: output, handledCharacters: handled) {
                let accepted = await onLicense(pending.prompt)
                guard stdin.write(accepted ? "y\n" : "n\n") else {
                    if process.isRunning { process.terminate() }
                    _ = await exit.value()
                    return .failed("The update could not answer the license prompt.")
                }
                if !accepted { declined = true }
                handled = pending.handledCharacters
            }
        }

        let code = await exit.value()
        if declined { return .declined }
        if timedOut.withLock({ $0 }) {
            return .failed("The update timed out.")
        }
        if code == 0 { return .updated }
        return .failed(SDKInstallReport.failureMessage(in: output))
    }
}

enum SDKLicensePromptParser {
    static let marker = "Accept? (y/N):"

    struct Pending {
        var prompt: SDKLicensePrompt
        var handledCharacters: Int
    }

    static func next(in output: String, handledCharacters: Int) -> Pending? {
        guard handledCharacters >= 0, handledCharacters <= output.count else { return nil }
        let start = output.index(output.startIndex, offsetBy: handledCharacters)
        guard let prompt = output[start...].range(of: marker) else { return nil }
        let block = String(output[start..<prompt.lowerBound]).replacingOccurrences(of: "\r", with: "\n")
        let handled = output.distance(from: output.startIndex, to: prompt.upperBound)
        return Pending(prompt: parse(block), handledCharacters: handled)
    }

    static func parse(_ block: String) -> SDKLicensePrompt {
        var name = "Android SDK license"
        var body: [String] = []
        var inBody = false
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("License "), text.hasSuffix(":") {
                let id = text.dropFirst("License ".count).dropLast()
                if !id.isEmpty { name = String(id) }
                continue
            }
            if text.hasPrefix("-----") {
                if inBody { break }
                inBody = true
                continue
            }
            if inBody { body.append(String(line)) }
        }
        let license = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = block.trimmingCharacters(in: .whitespacesAndNewlines)
        return SDKLicensePrompt(name: name, text: license.isEmpty ? fallback : license)
    }
}

enum SDKInstallReport {
    static func failureMessage(in output: String) -> String {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("Warning:")
                    && !line.hasPrefix("-----")
                    && line != SDKLicensePromptParser.marker
                    && !line.hasPrefix("License ")
            }
        if let failed = lines.last(where: { line in
            let lower = line.lowercased()
            return lower.contains("fail")
                || lower.contains("error")
                || lower.contains("not accepted")
                || lower.contains("unable")
        }) {
            return clip(failed)
        }
        if let last = lines.last { return clip(last) }
        return "The package could not be updated."
    }

    private static func clip(_ line: String) -> String {
        guard line.count > 240 else { return line }
        return String(line.prefix(239)) + "…"
    }
}

private actor ExitBox {
    private var code: Int32?
    private var received = false
    private var waiter: CheckedContinuation<Int32?, Never>?

    func finish(_ code: Int32?) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: code)
        } else {
            self.code = code
            received = true
        }
    }

    func value() async -> Int32? {
        if received {
            received = false
            return code
        }
        return await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }
}

private final class StandardInput: @unchecked Sendable {
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func write(_ text: String) -> Bool {
        do {
            try handle.write(contentsOf: Data(text.utf8))
            return true
        } catch {
            return false
        }
    }

    func close() {
        try? handle.close()
    }
}

private struct InstallStream {
    var data = Data()
    var finished = false
    var waiter: CheckedContinuation<Data?, Never>?
}

private enum InstallReady {
    case chunk(Data)
    case eof
    case parked
}

private final class InstallOutput: Sendable {
    private let state = Mutex(InstallStream())

    init(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self?.finish()
            } else {
                self?.append(chunk)
            }
        }
    }

    func wait(after seen: Int) async -> Data? {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> InstallReady in
                if state.data.count > seen { return .chunk(state.data) }
                if state.finished { return .eof }
                state.waiter = continuation
                return .parked
            }
            switch ready {
            case .chunk(let data): continuation.resume(returning: data)
            case .eof: continuation.resume(returning: nil)
            case .parked: break
            }
        }
    }

    func finish() {
        resume(state.withLock { state in
            state.finished = true
            return takeWaiter(from: &state)
        })
    }

    private func append(_ chunk: Data) {
        resume(state.withLock { state in
            guard !state.finished else { return nil }
            state.data.append(chunk)
            return takeWaiter(from: &state)
        })
    }

    private func takeWaiter(from state: inout InstallStream) -> (CheckedContinuation<Data?, Never>, Data)? {
        guard let waiter = state.waiter else { return nil }
        state.waiter = nil
        return (waiter, state.data)
    }

    private func resume(_ pending: (CheckedContinuation<Data?, Never>, Data)?) {
        pending?.0.resume(returning: pending?.1)
    }
}
