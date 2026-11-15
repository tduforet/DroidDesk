import Foundation
import Observation

/// One line of the guided setup, in the order the work happens.
enum SetupStep: String, CaseIterable, Identifiable, Sendable {
    case commandLineTools
    case platformTools
    case emulator
    case platform
    case buildTools
    case systemImage
    case device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandLineTools: "Command-line tools"
        case .platformTools: "Platform tools (adb)"
        case .emulator: "Emulator"
        case .platform: "Android platform"
        case .buildTools: "Build-tools"
        case .systemImage: "System image"
        case .device: "Virtual device"
        }
    }
}

enum SetupStepState: Equatable, Sendable {
    case pending
    case working
    case done
}

/// The newest stable packages a clean SDK gets. Chosen from `sdkmanager --list`.
struct SetupPlan: Equatable, Sendable {
    var platform: StudioPackage
    var buildTools: StudioPackage
    var image: PhoneSystemImage
}

/// Where the emulator of the guided setup stands once the device exists.
enum SetupDeviceStage: Equatable, Sendable {
    case none
    case stopped
    case starting
    case ready
}

/// Walks a new user from no SDK to a booted virtual device. Every step is read back from the disk,
/// so an interrupted or partly done setup resumes where it stopped.
@MainActor
@Observable
final class SetupModel {
    private static let dismissedKey = "setupDismissed"

    private(set) var isPresented = false
    private(set) var states: [SetupStep: SetupStepState] = [:]
    private(set) var isWorking = false
    private(set) var failure: String?
    private(set) var deviceName: String?
    private(set) var deviceStage: SetupDeviceStage = .none
    private(set) var licensePrompt: SDKLicensePrompt?
    private(set) var plan: SetupPlan?
    private(set) var folderRejection: String?
    private(set) var folder: URL

    private let runner = CommandRunner()
    private var licenseContinuation: CheckedContinuation<Bool, Never>?
    private var launchTask: Task<Void, Never>?

    init() {
        folder = SDKLocationStore.url ?? SDKLocator.existingRoot() ?? SDKLocator.conventionalRoot
        refreshStates()
        // A skipped setup stays skipped only while an SDK is still on disk. Without one, there is nothing to use yet.
        let sdkMissing = states[.commandLineTools] != .done
        let dismissed = UserDefaults.standard.bool(forKey: Self.dismissedKey)
        isPresented = !isComplete && (sdkMissing || !dismissed)
    }

    // MARK: Derived state

    /// Everything is installed and a device exists.
    var isComplete: Bool {
        SetupStep.allCases.allSatisfy { states[$0] == .done }
    }

    /// The SDK has to be installed before the folder can no longer change.
    var canChooseFolder: Bool {
        !isWorking && deviceStage == .none && states[.commandLineTools] != .done
    }

    var canLeave: Bool {
        !isWorking && deviceStage != .starting
    }

    var folderLine: String {
        SDKPathDisplay.tilde(folder)
    }

    var installPending: Bool {
        SetupStep.allCases.contains { $0 != .device && states[$0] != .done }
    }

    /// Plain-language headline for the primary action.
    var primaryTitle: String {
        if installPending || deviceName == nil { return "Install and create a device" }
        switch deviceStage {
        case .ready: return "Open Virtual Devices"
        case .starting: return "Starting…"
        default: return "Start the device"
        }
    }

    // MARK: Actions

    func chooseFolder() {
        guard canChooseFolder else { return }
        switch SDKFolderPicker.choose(startingAt: folder) {
        case .cancelled:
            return
        case .rejected:
            folderRejection = SDKInstallLocation.rejectionMessage
        case .selected(let url):
            folder = url
            folderRejection = nil
            refreshStates()
        }
    }

    func primaryAction() {
        guard !isWorking else { return }
        if installPending || deviceName == nil {
            runSetup()
        } else if deviceStage == .stopped {
            startDevice()
        }
    }

    func retry() {
        failure = nil
        primaryAction()
    }

    /// Leaves the setup without finishing it. The choice sticks until Settings runs the setup again.
    func skip() {
        guard canLeave else { return }
        UserDefaults.standard.set(true, forKey: Self.dismissedKey)
        isPresented = false
    }

    func finish() {
        guard canLeave else { return }
        isPresented = false
    }

    /// Settings runs the setup again, for example to add a device.
    func restart() {
        UserDefaults.standard.removeObject(forKey: Self.dismissedKey)
        failure = nil
        folder = SDKLocationStore.url ?? SDKLocator.existingRoot() ?? SDKLocator.conventionalRoot
        refreshStates()
        isPresented = true
    }

    func acceptLicense() {
        finishLicense(accepted: true)
    }

    func declineLicense() {
        finishLicense(accepted: false)
    }

    func declineLicenseIfNeeded() {
        guard licenseContinuation != nil else { return }
        finishLicense(accepted: false)
    }

    // MARK: Setup

    private func runSetup() {
        guard let root = SDKInstallLocation.accepted(folder) else {
            folderRejection = SDKInstallLocation.rejectionMessage
            return
        }
        folderRejection = nil
        failure = nil
        isWorking = true
        Task {
            await self.install(into: root)
            self.isWorking = false
        }
    }

    private func install(into root: URL) async {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            failure = "The SDK folder could not be created."
            return
        }
        SDKLocationStore.save(root)
        refreshStates()

        if states[.commandLineTools] != .done {
            states[.commandLineTools] = .working
            let outcome = await CommandLineToolsBootstrap().install(into: root)
            refreshStates()
            guard case .updated = outcome, states[.commandLineTools] == .done else {
                if case .failed(let message) = outcome {
                    failure = message
                } else {
                    failure = "The command-line tools could not be installed."
                }
                return
            }
        }

        guard let plan = await choosePlan(root: root) else {
            failure = "The list of Android packages could not be read. Check your connection and try again."
            return
        }
        self.plan = plan
        refreshStates()

        var identifiers: [String] = []
        var included: [SetupStep] = []
        func need(_ step: SetupStep, _ identifier: String) {
            guard states[step] != .done else { return }
            identifiers.append(identifier)
            included.append(step)
        }
        need(.platformTools, AndroidSDKPackage.platformTools.installIdentifier)
        need(.emulator, AndroidSDKPackage.emulator.installIdentifier)
        need(.platform, plan.platform.installIdentifier)
        need(.buildTools, plan.buildTools.installIdentifier)
        need(.systemImage, plan.image.installIdentifier)

        if !identifiers.isEmpty {
            for step in included { states[step] = .working }
            let outcome = await SDKInstaller().installPackages(
                identifiers,
                sdkRoot: root,
                environment: AndroidCommandEnvironment(sdkRoot: root).values
            ) { prompt in
                await self.confirm(prompt)
            }
            refreshStates()
            switch outcome {
            case .updated:
                break
            case .declined:
                failure = "The Android SDK licenses must be accepted to install these packages."
                return
            case .failed(let message):
                failure = message
                return
            }
            guard included.allSatisfy({ states[$0] == .done }) else {
                failure = "Some packages are still missing after the install."
                return
            }
        }

        if deviceName == nil {
            states[.device] = .working
            await createDevice(root: root, image: plan.image)
            refreshStates()
        }
    }

    private func choosePlan(root: URL) async -> SetupPlan? {
        let executable = root.appending(path: AndroidSDKTool.sdkmanager.executableRelativePath)
        guard let result = await runner.run(
            executable: executable,
            arguments: ["--list"],
            environment: AndroidCommandEnvironment(sdkRoot: root).values,
            timeout: .seconds(60)
        ), result.exitCode == 0 else { return nil }
        let images = PhoneSystemImageCatalogue.offered(in: result.standardOutput)
        let platforms = StudioPackageCatalogue.offeredPlatforms(in: result.standardOutput)
        let buildTools = StudioPackageCatalogue.offeredBuildTools(in: result.standardOutput)
        guard let image = images.first,
              let platform = platforms.first(where: { $0.version == image.api }) ?? platforms.first,
              let tools = buildTools.first else { return nil }
        return SetupPlan(platform: platform, buildTools: tools, image: image)
    }

    private func createDevice(root: URL, image: PhoneSystemImage) async {
        let environment = AndroidCommandEnvironment(sdkRoot: root).values
        let executable = root.appending(path: AndroidSDKTool.avdmanager.executableRelativePath)
        guard let listing = await runner.run(
            executable: executable,
            arguments: ["list", "device"],
            environment: environment,
            timeout: .seconds(60)
        ), listing.exitCode == 0,
              let profile = HardwareProfileCatalogue.phones(in: listing.standardOutput).first else {
            failure = "The hardware profiles could not be read."
            return
        }
        let name = AVDName.suggestion(profile: profile, image: image, taken: Set(Self.deviceNames()))
        let arguments = ["create", "avd", "-n", name, "-k", image.installIdentifier, "-d", profile.id]
        let activityID = ActivityLog.shared.begin(
            title: "Create \(name)",
            command: ActivityCommand.line(executable: executable, arguments: arguments)
        )
        let result = await runner.run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: .seconds(120)
        )
        let created = result?.exitCode == 0 && Self.deviceNames().contains(name)
        ActivityLog.shared.finish(
            activityID,
            exitCode: result?.exitCode,
            standardOutput: result?.standardOutput ?? "",
            standardError: created ? "" : (result?.standardError ?? "The command could not start."),
            outcome: created ? .succeeded : .failed
        )
        if !created {
            failure = "The virtual device could not be created."
        }
    }

    // MARK: Emulator

    private func startDevice() {
        guard let name = deviceName, let root = SDKLocator.existingRoot() else { return }
        deviceStage = .starting
        failure = nil
        launchTask = Task { [weak self] in
            let outcome = await EmulatorSession().run(avdName: name, sdkRoot: root) {
                self?.deviceStage = .ready
            }
            guard let self else { return }
            if case .failed(let message) = outcome {
                self.failure = message
            }
            self.deviceStage = .stopped
            self.launchTask = nil
        }
    }

    // MARK: Disk state

    /// Reads every step from the SDK folder instead of remembering what the app did.
    private func refreshStates() {
        let root = folder
        func ready(_ tool: AndroidSDKTool) -> Bool {
            FileManager.default.isExecutableFile(atPath: root.appending(path: tool.executableRelativePath).path)
        }
        func mark(_ step: SetupStep, _ done: Bool) {
            if done {
                states[step] = .done
            } else if states[step] != .working {
                states[step] = .pending
            }
        }
        mark(.commandLineTools, ready(.sdkmanager) && ready(.avdmanager))
        mark(.platformTools, ready(.adb))
        mark(.emulator, ready(.emulator))

        let installedPlatforms = StudioPackageDisk.installed(in: root).filter { $0.kind == .platform }
        let installedBuildTools = StudioPackageDisk.installed(in: root).filter { $0.kind == .buildTools }
        if let plan {
            mark(.platform, StudioPackageDisk.isInstalled(plan.platform, in: root))
            mark(.buildTools, StudioPackageDisk.isInstalled(plan.buildTools, in: root))
            mark(.systemImage, PhoneSystemImageCatalogue.isInstalled(plan.image, in: root))
        } else {
            mark(.platform, installedPlatforms.contains { AndroidAPIFloor.includes($0.version) })
            mark(.buildTools, installedBuildTools.contains { AndroidAPIFloor.includes($0.version) })
            mark(.systemImage, !PhoneSystemImageCatalogue.installed(in: root).isEmpty)
        }

        let names = Self.deviceNames()
        deviceName = deviceName.flatMap { names.contains($0) ? $0 : nil } ?? names.first
        mark(.device, deviceName != nil)
        if deviceName == nil {
            deviceStage = .none
        } else if deviceStage == .none {
            deviceStage = .stopped
        }
    }

    /// Names of the AVDs on this Mac, read from the `.ini` file each one leaves in the AVD folder.
    nonisolated private static func deviceNames() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: AVDLocation.directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return entries
            .filter { $0.pathExtension == "ini" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    // MARK: Licenses

    private func confirm(_ prompt: SDKLicensePrompt) async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                licenseContinuation = continuation
                licensePrompt = prompt
            }
        } onCancel: {
            Task { @MainActor in
                self.declineLicenseIfNeeded()
            }
        }
    }

    private func finishLicense(accepted: Bool) {
        let continuation = licenseContinuation
        licenseContinuation = nil
        licensePrompt = nil
        continuation?.resume(returning: accepted)
    }
}
