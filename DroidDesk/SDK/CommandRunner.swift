import Foundation
import Synchronization

struct CommandResult: Sendable, Equatable {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String
}

/// Runs one executable directly, without a shell. A timeout counts as a failure.
struct CommandRunner: Sendable {
    func succeeds(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration = .seconds(15)
    ) async -> Bool {
        await run(executable: executable, arguments: arguments, environment: environment, timeout: timeout)?.exitCode == 0
    }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration = .seconds(15)
    ) async -> CommandResult? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let reader = OutputReader(output.fileHandleForReading)
        let errorReader = OutputReader(errors.fileHandleForReading)

        let exitCode: Int32? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let gate = ResumeGate(continuation)
                process.terminationHandler = { process in
                    gate.resume(process.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    reader.finish()
                    errorReader.finish()
                    gate.resume(nil)
                    return
                }
                Task {
                    try? await Task.sleep(for: timeout)
                    if process.isRunning {
                        process.terminate()
                    }
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        let standardOutput = await reader.text()
        let standardError = await errorReader.text()
        guard let exitCode else { return nil }
        return CommandResult(exitCode: exitCode, standardOutput: standardOutput, standardError: standardError)
    }
}

final class ResumeGate<Value: Sendable>: Sendable {
    private let slot = Mutex<CheckedContinuation<Value, Never>?>(nil)

    init(_ continuation: CheckedContinuation<Value, Never>) {
        slot.withLock { $0 = continuation }
    }

    func resume(_ value: Value) {
        let continuation = slot.withLock { slot in
            let continuation = slot
            slot = nil
            return continuation
        }
        continuation?.resume(returning: value)
    }
}

private struct OutputBuffer {
    var data = Data()
    var finished = false
    var waiters: [CheckedContinuation<String, Never>] = []
}

private final class OutputReader: Sendable {
    private let buffer = Mutex(OutputBuffer())

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

    func text() async -> String {
        await withCheckedContinuation { continuation in
            let ready = buffer.withLock { buffer -> String? in
                guard buffer.finished else {
                    buffer.waiters.append(continuation)
                    return nil
                }
                return String(decoding: buffer.data, as: UTF8.self)
            }
            if let ready {
                continuation.resume(returning: ready)
            }
        }
    }

    func finish() {
        let pending = buffer.withLock { buffer -> (String, [CheckedContinuation<String, Never>])? in
            guard !buffer.finished else { return nil }
            buffer.finished = true
            let text = String(decoding: buffer.data, as: UTF8.self)
            let waiters = buffer.waiters
            buffer.waiters.removeAll()
            return (text, waiters)
        }
        guard let pending else { return }
        for waiter in pending.1 {
            waiter.resume(returning: pending.0)
        }
    }

    private func append(_ chunk: Data) {
        buffer.withLock { $0.data.append(chunk) }
    }
}
