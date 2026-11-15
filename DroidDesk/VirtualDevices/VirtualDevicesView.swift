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

                if model.showsSystemImages {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("System images")
                            .font(.headline)
                        systemImageGroup
                            .accessibilityLabel("System images")
                    }
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

    private var systemImageGroup: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.systemImages.enumerated()), id: \.element.id) { index, status in
                systemImageRow(status)
                if index < model.systemImages.count - 1 {
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

    private func systemImageRow(_ status: PhoneSystemImageStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.image.title)
                HStack(spacing: 6) {
                    StatusDot(
                        color: status.isInstalled ? .green : .red,
                        label: status.isInstalled ? "Ready" : "Missing"
                    )
                    Text(status.image.detail)
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospaced())
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            if model.installingImageID == status.id {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Installing API \(status.image.api) system image")
            } else if !status.isInstalled {
                Button("Install") { model.install(status.image) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isInstallingImage)
                    .accessibilityLabel("Install API \(status.image.api) system image")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
                HStack(spacing: 6) {
                    Text(device.title)
                    if model.deletingName != device.name {
                        deviceStatusMark(model.phase(for: device))
                    }
                }
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
                if model.phase(for: device) == .missingImage {
                    Text(model.phase(for: device).label)
                        .foregroundStyle(model.phase(for: device).color)
                }
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
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
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

    @ViewBuilder
    private func deviceStatusMark(_ phase: DevicePhase) -> some View {
        switch phase {
        case .ready:
            PulsingStatusDot(color: .green, label: "Ready")
        case .starting:
            StatusDot(color: .orange, label: "Starting")
        case .stopped:
            StatusDot(color: .red, label: "Stopped")
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
    private(set) var systemImages: [PhoneSystemImageStatus] = []
    private(set) var avdmanagerReady = false
    private(set) var isChecking = false
    private(set) var installingImageID: String?
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

    var showsSystemImages: Bool { !systemImages.isEmpty || isInstallingImage }
    var isInstallingImage: Bool { installingImageID != nil }
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

    func install(_ image: PhoneSystemImage) {
        guard installingImageID == nil, let root = SDKLocator.existingRoot() else { return }
        guard systemImages.contains(where: { $0.id == image.id && !$0.isInstalled }) else { return }
        installingImageID = image.id
        failureTitle = "Install failed"
        installError = nil
        Task {
            let outcome = await SDKInstaller().installPackages(
                [image.installIdentifier],
                sdkRoot: root,
                environment: AndroidCommandEnvironment(sdkRoot: root).values
            ) { prompt in
                await self.confirm(prompt)
            }
            switch outcome {
            case .updated:
                await self.load()
                if !PhoneSystemImageCatalogue.isInstalled(image, in: root) {
                    self.installError = "The package could not be installed."
                }
            case .declined:
                break
            case .failed(let message):
                self.failureTitle = "Install failed"
                self.installError = message
            }
            self.installingImageID = nil
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
        systemImages = await systemImages(in: root)
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

    private func systemImages(in root: URL?) async -> [PhoneSystemImageStatus] {
        imageListFailed = false
        guard let root else { return [] }
        let installed = PhoneSystemImageCatalogue.installed(in: root)
        var byIdentifier = Dictionary(uniqueKeysWithValues: installed.map {
            ($0.id, PhoneSystemImageStatus(image: $0, isInstalled: true))
        })
        let executable = root.appending(path: AndroidSDKTool.sdkmanager.executableRelativePath)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return sorted(Array(byIdentifier.values))
        }
        guard let result = await runner.run(
            executable: executable,
            arguments: ["--list"],
            environment: AndroidCommandEnvironment(sdkRoot: root).values,
            timeout: .seconds(30)
        ), result.exitCode == 0 else {
            imageListFailed = true
            return sorted(Array(byIdentifier.values))
        }
        for image in PhoneSystemImageCatalogue.offered(in: result.standardOutput) where byIdentifier[image.id] == nil {
            byIdentifier[image.id] = PhoneSystemImageStatus(image: image, isInstalled: false)
        }
        return sorted(Array(byIdentifier.values))
    }

    private func sorted(_ statuses: [PhoneSystemImageStatus]) -> [PhoneSystemImageStatus] {
        statuses.sorted { VersionOrdering.isOlder($1.image.api, than: $0.image.api) }
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

private struct StatusDot: View {
    var color: Color
    var label: String

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(label)
    }
}

/// A live device: the dot stays put and a ring expands until it fades.
private struct PulsingStatusDot: View {
    var color: Color
    var label: String
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.45))
                .scaleEffect(pulsing ? 2.4 : 1)
                .opacity(pulsing ? 0 : 1)
            Circle()
                .fill(color)
        }
        .frame(width: 8, height: 8)
        .accessibilityLabel(label)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
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
