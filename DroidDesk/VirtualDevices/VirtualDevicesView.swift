import SwiftUI

struct VirtualDevicesView: View {
    var model: VirtualDevicesModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isChecking && model.devices.isEmpty ? "Checking devices…" : "Virtual devices")
                        .font(.title2.weight(.semibold))
                    Text(model.path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Devices already on this Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                if model.showsSystemImage {
                    systemImageRow
                        .accessibilityLabel("System image")
                }
                if !model.devices.isEmpty {
                    deviceGroup(model.devices)
                        .accessibilityLabel("Virtual devices")
                }
                if let note = model.note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .navigationTitle("Virtual Devices")
        .task { await model.refresh() }
        .sheet(isPresented: deleteSheetPresented) {
            if let device = model.deleteTarget {
                DeleteDeviceSheet(
                    device: device,
                    cancel: model.cancelDelete,
                    confirm: model.confirmDelete
                )
            }
        }
    }

    private var deleteSheetPresented: Binding<Bool> {
        Binding(
            get: { model.deleteTarget != nil },
            set: { isPresented in
                if !isPresented { model.cancelDelete() }
            }
        )
    }

    private var systemImageRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PhoneSystemImage.title)
                Text(PhoneSystemImage.detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            if model.isInstallingImage {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Installing the system image")
            } else if model.systemImage == .ready {
                Text("Ready")
                    .foregroundStyle(.green)
            } else {
                Button("Install", action: model.installSystemImage)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isInstallingImage)
                    .accessibilityLabel("Install the system image")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }

    private func deviceGroup(_ devices: [VirtualDevice]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                deviceRow(device)
                if index < devices.count - 1 {
                    Divider()
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
        .accessibilityElement(children: .contain)
    }

    private func deviceRow(_ device: VirtualDevice) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.title)
                if !device.detail.isEmpty {
                    Text(device.detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            if model.deletingName == device.name {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Deleting \(device.title)")
                Text("Deleting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                deviceControls(device)
                Button {
                    model.requestDelete(device)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .disabled(model.isDeletingDevice || model.isInstallingImage)
                .accessibilityLabel("Delete \(device.title)")
                Text(model.phase(for: device).label)
                    .foregroundStyle(model.phase(for: device).color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func deviceControls(_ device: VirtualDevice) -> some View {
        switch model.phase(for: device) {
        case .stopped:
            Button {
                model.play(device)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isStartingDevice)
            .accessibilityLabel("Play \(device.title)")
        case .starting:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Starting \(device.title)")
            Button {
                model.stop(device)
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Stop \(device.title)")
        case .ready:
            Button {
                model.stop(device)
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Stop \(device.title)")
        case .missingImage:
            EmptyView()
        }
    }
}

/// Confirms before one virtual device is deleted. Cancel is the escape action.
private struct DeleteDeviceSheet: View {
    var device: VirtualDevice
    var cancel: () -> Void
    var confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete \(device.title)?")
                .font(.title2.weight(.semibold))
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive, action: confirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var message: String {
        if device.title == device.name {
            "This permanently deletes this virtual device. The system image stays installed."
        } else {
            "This permanently deletes \(device.name). The system image stays installed."
        }
    }
}

@MainActor
@Observable
final class VirtualDevicesModel {
    private(set) var devices: [VirtualDevice] = []
    private(set) var systemImage: SystemImageState?
    private(set) var avdmanagerReady = false
    private(set) var isChecking = false
    private(set) var isInstallingImage = false
    private(set) var listFailed = false
    private(set) var imageListFailed = false
    private(set) var deleteTarget: VirtualDevice?
    private(set) var deletingName: String?
    private(set) var phases: [String: DevicePhase] = [:]
    private var launchTasks: [String: Task<Void, Never>] = [:]
    private(set) var licensePrompt: SDKLicensePrompt?
    private(set) var failureTitle = "Install failed"
    private(set) var installError: String?
    private var licenseContinuation: CheckedContinuation<Bool, Never>?
    private let runner = CommandRunner()

    var showsSystemImage: Bool { systemImage != nil || isInstallingImage }
    var isStartingDevice: Bool { phases.values.contains(.starting) }
    var isDeletingDevice: Bool { deletingName != nil }

    func phase(for device: VirtualDevice) -> DevicePhase {
        if device.readiness == .missingImage { return .missingImage }
        return phases[device.name] ?? .stopped
    }

    var path: String {
        SDKPathDisplay.tilde(AVDLocation.directory)
    }

    var note: String? {
        if !avdmanagerReady { return "Install avdmanager on the Dashboard first." }
        if listFailed { return "The device list could not be read." }
        if imageListFailed { return "The package list could not be read." }
        if !isChecking && devices.isEmpty { return "No virtual devices." }
        return nil
    }

    func refresh() async {
        guard !isInstallingImage, deletingName == nil else { return }
        await load()
    }

    func installSystemImage() {
        guard !isInstallingImage, systemImage == .missing, let root = SDKLocator.existingRoot() else { return }
        isInstallingImage = true
        failureTitle = "Install failed"
        installError = nil
        Task {
            let outcome = await SDKInstaller().installPackages(
                [PhoneSystemImage.installIdentifier],
                sdkRoot: root,
                environment: AndroidCommandEnvironment(sdkRoot: root).values
            ) { prompt in
                await self.confirm(prompt)
            }
            switch outcome {
            case .updated:
                await self.load()
                if !PhoneSystemImage.isInstalled(in: root) {
                    self.installError = "The package could not be installed."
                }
            case .declined:
                break
            case .failed(let message):
                self.failureTitle = "Install failed"
                self.installError = message
            }
            self.isInstallingImage = false
        }
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

    func dismissInstallError() {
        installError = nil
    }

    private func load() async {
        isChecking = true
        listFailed = false
        let root = SDKLocator.existingRoot()
        let executable = root?.appending(path: AndroidSDKTool.avdmanager.executableRelativePath)
        let ready = executable.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false
        avdmanagerReady = ready
        let listed = await devices(executable: ready ? executable : nil, root: root)
        if ready && listed == nil {
            listFailed = true
        }
        devices = listed ?? []
        systemImage = await systemImage(in: root)
        await adoptRunningEmulators(in: root)
        isChecking = false
    }

    func play(_ device: VirtualDevice) {
        guard phase(for: device) == .stopped, !isInstallingImage, let root = SDKLocator.existingRoot() else { return }
        let executable = root.appending(path: AndroidSDKTool.emulator.executableRelativePath)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            failureTitle = "Start failed"
            installError = "Install the emulator on the Dashboard first."
            return
        }
        let name = device.name
        phases[name] = .starting
        failureTitle = "Start failed"
        installError = nil
        launchTasks[name]?.cancel()
        launchTasks[name] = Task { [weak self] in
            let outcome = await EmulatorSession().run(avdName: name, sdkRoot: root) {
                self?.phases[name] = .ready
            }
            guard let self else { return }
            switch outcome {
            case .ended:
                self.phases[name] = nil
            case .failed(let message):
                self.phases[name] = nil
                self.failureTitle = "Start failed"
                self.installError = message
            }
            self.launchTasks[name] = nil
        }
    }

    func requestDelete(_ device: VirtualDevice) {
        guard deletingName == nil, !isInstallingImage else { return }
        deleteTarget = device
    }

    func cancelDelete() {
        deleteTarget = nil
    }

    func confirmDelete() {
        guard deletingName == nil, let device = deleteTarget, let root = SDKLocator.existingRoot() else { return }
        let name = device.name
        guard devices.contains(where: { $0.name == name }) else {
            deleteTarget = nil
            return
        }
        deleteTarget = nil
        deletingName = name
        failureTitle = "Delete failed"
        installError = nil
        Task {
            await self.stopForDeletion(name, sdkRoot: root)
            let executable = root.appending(path: AndroidSDKTool.avdmanager.executableRelativePath)
            let result = await self.runner.run(
                executable: executable,
                arguments: ["delete", "avd", "-n", name],
                environment: AndroidCommandEnvironment(sdkRoot: root).values,
                timeout: .seconds(120)
            )
            self.phases[name] = nil
            await self.load()
            if result?.exitCode != 0 || self.devices.contains(where: { $0.name == name }) {
                self.failureTitle = "Delete failed"
                self.installError = "The device could not be deleted."
            }
            self.deletingName = nil
        }
    }

    func stop(_ device: VirtualDevice) {
        if let task = launchTasks[device.name] {
            task.cancel()
            return
        }
        let name = device.name
        guard phases[name] == .ready, let root = SDKLocator.existingRoot() else { return }
        phases[name] = nil
        Task {
            await EmulatorSession().stop(avdName: name, sdkRoot: root)
        }
    }

    private func stopForDeletion(_ name: String, sdkRoot: URL) async {
        if let task = launchTasks[name] {
            task.cancel()
            await task.value
        }
        await EmulatorSession().stop(avdName: name, sdkRoot: sdkRoot)
        phases[name] = nil
    }

    private func adoptRunningEmulators(in root: URL?) async {
        guard let root else { return }
        let booted = await EmulatorCensus.bootedNames(sdkRoot: root)
        for name in booted where phases[name] != .starting {
            phases[name] = .ready
        }
        for name in phases.keys where phases[name] == .ready && !booted.contains(name) && launchTasks[name] == nil {
            phases[name] = nil
        }
    }

    private func systemImage(in root: URL?) async -> SystemImageState? {
        imageListFailed = false
        guard let root else { return nil }
        if PhoneSystemImage.isInstalled(in: root) { return .ready }
        let executable = root.appending(path: AndroidSDKTool.sdkmanager.executableRelativePath)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        guard let result = await runner.run(
            executable: executable,
            arguments: ["--list"],
            environment: AndroidCommandEnvironment(sdkRoot: root).values,
            timeout: .seconds(30)
        ), result.exitCode == 0 else {
            imageListFailed = true
            return nil
        }
        return PhoneSystemImage.catalogueContains(result.standardOutput) ? .missing : nil
    }

    private func devices(executable: URL?, root: URL?) async -> [VirtualDevice]? {
        guard let executable, let root else { return nil }
        guard let result = await runner.run(
            executable: executable,
            arguments: ["list", "avd"],
            environment: AndroidCommandEnvironment(sdkRoot: root).values,
            timeout: .seconds(15)
        ) else { return nil }
        let entries = AVDListing.entries(in: result.standardOutput)
        if result.exitCode != 0 && entries.isEmpty { return nil }
        return entries
            .map { VirtualDeviceReader.device(from: $0, sdkRoot: root) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

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

enum SystemImageState: Equatable, Sendable {
    case missing
    case ready
}

enum DevicePhase: Equatable, Sendable {
    case missingImage
    case stopped
    case starting
    case ready

    var label: String {
        switch self {
        case .missingImage: "Missing image"
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .ready: "Ready"
        }
    }

    var color: Color {
        switch self {
        case .missingImage: .red
        case .ready: .green
        case .stopped, .starting: .secondary
        }
    }
}

/// AVDs `adb` can already see with a finished boot. Used when an emulator was started earlier.
enum EmulatorCensus {
    static func bootedNames(sdkRoot: URL) async -> Set<String> {
        let session = EmulatorSession()
        return await session.bootedAVDNames(sdkRoot: sdkRoot)
    }
}
