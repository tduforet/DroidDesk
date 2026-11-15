import Darwin
import Foundation
import Synchronization

enum EmulatorOutcome: Sendable {
    case ended
    case failed(String)
}

/// Starts one AVD with the official `emulator` binary and watches `adb` until it has booted.
struct EmulatorSession: Sendable {
    private let runner = CommandRunner()

    func bootedAVDNames(sdkRoot: URL) async -> Set<String> {
        guard let result = await adb(sdkRoot, arguments: ["devices"]) else { return [] }
        var names: Set<String> = []
        for candidate in ADBDeviceList.emulatorSerials(in: result.standardOutput) {
            guard let name = await emulatorName(of: candidate, sdkRoot: sdkRoot),
                  await booted(candidate, sdkRoot: sdkRoot) else { continue }
            names.insert(name)
        }
        return names
    }

    func stop(avdName: String, sdkRoot: URL) async {
        let executable = sdkRoot.appending(path: AndroidSDKTool.adb.executableRelativePath)
        guard let serial = await serial(for: avdName, sdkRoot: sdkRoot) else { return }
        let arguments = ["-s", serial, "emu", "kill"]
        let id = await ActivityLog.shared.begin(
            title: "Stop \(avdName)",
            command: ActivityCommand.line(executable: executable, arguments: arguments)
        )
        let result = await adb(sdkRoot, arguments: arguments)
        await ActivityLog.shared.finish(
            id,
            exitCode: result?.exitCode,
            standardOutput: result?.standardOutput ?? "",
            standardError: result?.standardError ?? "The command could not start.",
            outcome: result?.exitCode == 0 ? .succeeded : .failed
        )
    }

    func run(
        avdName: String,
        sdkRoot: URL,
        onReady: @escaping @MainActor () -> Void
    ) async -> EmulatorOutcome {
        let executable = sdkRoot.appending(path: AndroidSDKTool.emulator.executableRelativePath)
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        let arguments = EmulatorLaunchArguments.arguments(avdName: avdName, sdkRoot: sdkRoot)
        process.arguments = arguments
        process.environment = AndroidCommandEnvironment(sdkRoot: sdkRoot).values
        let activityID = await ActivityLog.shared.begin(
            title: "Start \(avdName)",
            command: ActivityCommand.line(executable: executable, arguments: arguments)
        )
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        let outputDrain = OutputDrain(output.fileHandleForReading)
        let errorDrain = OutputDrain(errors.fileHandleForReading)
        let serial = SerialBox()

        do {
            try process.run()
        } catch {
            await ActivityLog.shared.finish(
                activityID,
                exitCode: nil,
                standardOutput: "",
                standardError: "The emulator could not start.",
                outcome: .failed
            )
            return .failed("The emulator could not start.")
        }

        let outcome = await withTaskCancellationHandler {
            await watch(
                avdName: avdName,
                sdkRoot: sdkRoot,
                process: process,
                outputDrain: outputDrain,
                errorDrain: errorDrain,
                serial: serial,
                onReady: onReady
            )
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        let succeeded = if case .ended = outcome { true } else { false }
        await ActivityLog.shared.finish(
            activityID,
            exitCode: process.isRunning ? nil : process.terminationStatus,
            standardOutput: outputDrain.text(),
            standardError: errorDrain.text(),
            outcome: succeeded ? .succeeded : .failed
        )
        return outcome
    }

    private func watch(
        avdName: String,
        sdkRoot: URL,
        process: Process,
        outputDrain: OutputDrain,
        errorDrain: OutputDrain,
        serial: SerialBox,
        onReady: @escaping @MainActor () -> Void
    ) async -> EmulatorOutcome {
        let deadline = ContinuousClock.now.advanced(by: .seconds(360))
        var announcedReady = false
        var missedAfterExit = 0

        while !Task.isCancelled {
            if let found = await self.serial(for: avdName, sdkRoot: sdkRoot) {
                serial.value = found
                missedAfterExit = 0
                if await booted(found, sdkRoot: sdkRoot), !announcedReady {
                    announcedReady = true
                    await onReady()
                }
            } else if !process.isRunning {
                let text = outputDrain.text() + "\n" + errorDrain.text()
                if !announcedReady, text.contains("ERROR") {
                    return .failed(failureMessage(text))
                }
                missedAfterExit += 1
                if announcedReady || missedAfterExit >= 15 { break }
            }

            if !announcedReady, ContinuousClock.now >= deadline {
                await shutdown(process: process, serial: serial.value, sdkRoot: sdkRoot)
                return .failed("The emulator did not finish starting.")
            }

            try? await Task.sleep(for: .seconds(2))
        }

        await shutdown(process: process, serial: serial.value, sdkRoot: sdkRoot)
        if announcedReady || Task.isCancelled { return .ended }
        return .failed(failureMessage(outputDrain.text() + "\n" + errorDrain.text()))
    }

    private func serial(for avdName: String, sdkRoot: URL) async -> String? {
        guard let result = await adb(sdkRoot, arguments: ["devices"]) else { return nil }
        for candidate in ADBDeviceList.emulatorSerials(in: result.standardOutput) {
            guard let name = await emulatorName(of: candidate, sdkRoot: sdkRoot) else { continue }
            if name == avdName { return candidate }
        }
        return nil
    }

    private func emulatorName(of serial: String, sdkRoot: URL) async -> String? {
        guard let result = await adb(sdkRoot, arguments: ["-s", serial, "emu", "avd", "name"]),
              result.exitCode == 0 else { return nil }
        return ADBDeviceList.avdName(in: result.standardOutput)
    }

    private func booted(_ serial: String, sdkRoot: URL) async -> Bool {
        guard let result = await adb(
            sdkRoot,
            arguments: ["-s", serial, "shell", "getprop", "sys.boot_completed"]
        ) else { return false }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private func shutdown(process: Process, serial: String?, sdkRoot: URL) async {
        if let serial {
            _ = await adb(sdkRoot, arguments: ["-s", serial, "emu", "kill"])
        }
        if process.isRunning { process.terminate() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func adb(_ sdkRoot: URL, arguments: [String]) async -> CommandResult? {
        let executable = sdkRoot.appending(path: AndroidSDKTool.adb.executableRelativePath)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return await runner.run(
            executable: executable,
            arguments: arguments,
            environment: AndroidCommandEnvironment(sdkRoot: sdkRoot).values,
            timeout: .seconds(15)
        )
    }

    private func failureMessage(_ output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if let line = lines.last(where: { line in
            let lower = line.lowercased()
            return lower.contains("error") || lower.contains("fatal") || lower.contains("panic")
        }) {
            return line.count > 240 ? String(line.prefix(239)) + "…" : line
        }
        return "The emulator could not start."
    }
}

/// Passes a plain width×height skin when the AVD's device skin is no longer in the SDK.
enum EmulatorLaunchArguments {
    static func arguments(avdName: String, sdkRoot: URL) -> [String] {
        var arguments = ["-avd", avdName]
        if let size = missingSkinSize(avdName: avdName, sdkRoot: sdkRoot) {
            arguments += ["-skin", size]
        }
        return arguments
    }

    private static func missingSkinSize(avdName: String, sdkRoot: URL) -> String? {
        let config = configuration(avdName: avdName)
        guard !skinIsInstalled(config, sdkRoot: sdkRoot) else { return nil }
        if let name = config["skin.name"], name.wholeMatch(of: /^\d+x\d+$/) != nil { return nil }
        guard let width = config["hw.lcd.width"], let height = config["hw.lcd.height"],
              Int(width) != nil, Int(height) != nil else { return nil }
        return "\(width)x\(height)"
    }

    private static func skinIsInstalled(_ config: [String: String], sdkRoot: URL) -> Bool {
        if let path = useful(config["skin.path"]), directoryExists(path) { return true }
        guard let name = useful(config["skin.name"]) else { return true }
        let roots = [
            sdkRoot.appending(path: "skins/\(name)", directoryHint: .isDirectory),
            sdkRoot.appending(path: "emulator/skins/\(name)", directoryHint: .isDirectory),
        ]
        return roots.contains { directoryExists($0.path) }
    }

    private static func configuration(avdName: String) -> [String: String] {
        let pointer = AVDConfig.values(in: AVDLocation.directory.appending(path: "\(avdName).ini"))
        let directory = pointer["path"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? AVDLocation.directory.appending(path: "\(avdName).avd", directoryHint: .isDirectory)
        return AVDConfig.read(directory: directory)
    }

    private static func directoryExists(_ path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func useful(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ADBDeviceList {
    static func emulatorSerials(in output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2, parts[0].hasPrefix("emulator-"), parts[1] == "device" else { return nil }
            return parts[0]
        }
    }

    static func avdName(in output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "OK" && $0 != "KO" }
    }
}

private final class SerialBox: @unchecked Sendable {
    var value: String?
}

/// Keeps an emulator's pipes empty so a long run cannot block on a full buffer.
private final class OutputDrain: @unchecked Sendable {
    private let state = Mutex(Data())

    init(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.append(chunk)
            }
        }
    }

    func text() -> String {
        let data = state.withLock { $0 }
        return String(decoding: data, as: UTF8.self)
    }

    private func append(_ chunk: Data) {
        state.withLock { data in
            data.append(chunk)
            if data.count > 16_384 {
                data.removeFirst(data.count - 16_384)
            }
        }
    }
}
