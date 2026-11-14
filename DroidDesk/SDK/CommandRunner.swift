import Foundation

/// Runs one executable directly, without a shell. A non-zero exit or a timeout counts as a failure.
struct CommandRunner: Sendable {
    func succeeds(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration = .seconds(15)
    ) async -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let gate = ResumeGate(continuation)
                process.terminationHandler = { process in
                    gate.resume(process.terminationStatus == 0)
                }
                do {
                    try process.run()
                } catch {
                    gate.resume(false)
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
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
