import SwiftUI

struct VirtualDevicesView: View {
    var model: VirtualDevicesModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Virtual devices")
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
                    createControl
                }

                if !model.devicesLoaded {
                    SkeletonGroup(rows: 2, label: "Loading virtual devices")
                }
                if !model.devices.isEmpty {
                    deviceGroup(model.devices)
                        .accessibilityLabel("Virtual devices")
                }
                if model.hasLoaded, let note = model.note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if model.showsSystemImages {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("System images")
                            .font(.headline)
                        systemImageGroup
                            .accessibilityLabel("System images")
                    }
                } else if !model.hasLoaded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("System images")
                            .font(.headline)
                        SkeletonGroup(rows: 2, label: "Loading system images")
                    }
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
        .sheet(isPresented: Binding(get: { model.showsCreateSheet }, set: { model.showsCreateSheet = $0 })) {
            CreateDeviceSheet(
                profiles: model.creationProfiles,
                images: model.installedImages,
                takenNames: model.takenNames,
                cancel: { model.showsCreateSheet = false },
                create: model.create
            )
        }
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

    @ViewBuilder
    private var createControl: some View {
        if model.isCreatingDevice || model.isPreparingCreation {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(model.isCreatingDevice ? "Creating…" : "Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Button {
                model.beginCreate()
            } label: {
                Label("New Device", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canCreateDevice)
            .help(model.installedImages.isEmpty ? "Install a system image first." : "Create a virtual device")
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
                    .disabled(model.isInstallingImage || model.isCreatingDevice)
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
                        .frame(width: 16, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .disabled(model.isDeletingDevice || model.isInstallingImage || model.isCreatingDevice)
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
                    .frame(width: 16, height: 14)
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
                    .frame(width: 16, height: 14)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Stop \(device.title)")
        case .ready:
            Button {
                model.stop(device)
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 16, height: 14)
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

/// Collects a name, a Pixel profile, and an installed system image for a new virtual device.
private struct CreateDeviceSheet: View {
    var profiles: [HardwareProfile]
    var images: [PhoneSystemImage]
    var takenNames: Set<String>
    var cancel: () -> Void
    var create: (String, HardwareProfile, PhoneSystemImage) -> Void

    @State private var profileID: String
    @State private var imageID: String
    @State private var name: String
    @State private var nameEdited = false

    init(
        profiles: [HardwareProfile],
        images: [PhoneSystemImage],
        takenNames: Set<String>,
        cancel: @escaping () -> Void,
        create: @escaping (String, HardwareProfile, PhoneSystemImage) -> Void
    ) {
        self.profiles = profiles
        self.images = images
        self.takenNames = takenNames
        self.cancel = cancel
        self.create = create
        let profile = profiles.first(where: { $0.id == "pixel_8a" }) ?? profiles.first
        let image = images.first
        _profileID = State(initialValue: profile?.id ?? "")
        _imageID = State(initialValue: image?.id ?? "")
        _name = State(initialValue: Self.suggestion(profile: profile, image: image, taken: takenNames))
    }

    private var profile: HardwareProfile? { profiles.first { $0.id == profileID } }
    private var image: PhoneSystemImage? { images.first { $0.id == imageID } }
    private var normalizedName: String { AVDName.normalized(name) }

    private var problem: String? {
        if normalizedName.isEmpty { return nil }
        if !AVDName.isValid(normalizedName) { return "Use letters, digits, dots, dashes, and underscores." }
        if takenNames.contains(normalizedName) { return "A device with this name already exists." }
        return nil
    }

    private var canCreate: Bool {
        profile != nil && image != nil && !normalizedName.isEmpty && problem == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New virtual device")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $name)
                    .onChange(of: name) { _, _ in
                        if name != Self.suggestion(profile: profile, image: image, taken: takenNames) {
                            nameEdited = true
                        }
                    }
                Picker("Hardware", selection: $profileID) {
                    ForEach(profiles) { Text($0.name).tag($0.id) }
                }
                Picker("System image", selection: $imageID) {
                    ForEach(images) { Text("API \($0.api) · Google Play").tag($0.id) }
                }
            }
            .onChange(of: profileID) { _, _ in suggestIfUntouched() }
            .onChange(of: imageID) { _, _ in suggestIfUntouched() }
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    guard let profile, let image else { return }
                    create(normalizedName, profile, image)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func suggestIfUntouched() {
        guard !nameEdited else { return }
        name = Self.suggestion(profile: profile, image: image, taken: takenNames)
        nameEdited = false
    }

    private static func suggestion(profile: HardwareProfile?, image: PhoneSystemImage?, taken: Set<String>) -> String {
        guard let profile, let image else { return "" }
        return AVDName.suggestion(profile: profile, image: image, taken: taken)
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
    private(set) var hasLoaded = false
    private(set) var devicesLoaded = false
    private(set) var installingImageID: String?
    private(set) var listFailed = false
    private(set) var imageListFailed = false
    private(set) var deleteTarget: VirtualDevice?
    private(set) var deletingName: String?
    private(set) var creatingName: String?
    private(set) var creationProfiles: [HardwareProfile] = []
    private(set) var isPreparingCreation = false
    private var profileCache: (root: String, profiles: [HardwareProfile])?
    private var profileTask: (root: String, task: Task<[HardwareProfile]?, Never>)?
    var showsCreateSheet = false
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
    var isCreatingDevice: Bool { creatingName != nil }
    var installedImages: [PhoneSystemImage] { systemImages.filter(\.isInstalled).map(\.image) }
    var canCreateDevice: Bool {
        avdmanagerReady && !installedImages.isEmpty && !isInstallingImage && !isDeletingDevice
            && !isCreatingDevice && !isPreparingCreation
    }
    var takenNames: Set<String> { Set(devices.map(\.name)) }

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
        guard !isInstallingImage, deletingName == nil, creatingName == nil else { return }
        await load()
        prefetchProfiles()
    }

    /// Opens the create sheet at once when the profiles are cached, otherwise reads them first.
    func beginCreate() {
        guard canCreateDevice, let root = SDKLocator.existingRoot() else { return }
        failureTitle = "Create failed"
        installError = nil
        if let cached = cachedProfiles(for: root) {
            creationProfiles = cached
            showsCreateSheet = true
            return
        }
        isPreparingCreation = true
        Task {
            let profiles = await self.hardwareProfiles(root: root)
            self.isPreparingCreation = false
            guard let profiles else {
                self.installError = "The hardware profiles could not be read."
                return
            }
            self.creationProfiles = profiles
            self.showsCreateSheet = true
        }
    }

    private func prefetchProfiles() {
        guard avdmanagerReady, let root = SDKLocator.existingRoot(), cachedProfiles(for: root) == nil else { return }
        Task { _ = await self.hardwareProfiles(root: root) }
    }

    private func cachedProfiles(for root: URL) -> [HardwareProfile]? {
        guard let cache = profileCache, cache.root == root.path else { return nil }
        return cache.profiles
    }

    /// `avdmanager list device` starts a JVM, so the result is kept until the SDK location changes.
    private func hardwareProfiles(root: URL) async -> [HardwareProfile]? {
        if let cached = cachedProfiles(for: root) { return cached }
        if let pending = profileTask, pending.root == root.path { return await pending.task.value }
        let runner = runner
        let environment = AndroidCommandEnvironment(sdkRoot: root).values
        let executable = root.appending(path: AndroidSDKTool.avdmanager.executableRelativePath)
        let task = Task<[HardwareProfile]?, Never> {
            guard let result = await runner.run(
                executable: executable,
                arguments: ["list", "device"],
                environment: environment,
                timeout: .seconds(30)
            ), result.exitCode == 0 else { return nil }
            let profiles = HardwareProfileCatalogue.phones(in: result.standardOutput)
            return profiles.isEmpty ? nil : profiles
        }
        profileTask = (root.path, task)
        let profiles = await task.value
        if profileTask?.root == root.path { profileTask = nil }
        if let profiles { profileCache = (root.path, profiles) }
        return profiles
    }

    func create(name: String, profile: HardwareProfile, image: PhoneSystemImage) {
        guard creatingName == nil, let root = SDKLocator.existingRoot() else { return }
        guard AVDName.isValid(name), !takenNames.contains(name),
              PhoneSystemImageCatalogue.isInstalled(image, in: root) else { return }
        showsCreateSheet = false
        creatingName = name
        failureTitle = "Create failed"
        installError = nil
        Task {
            let executable = root.appending(path: AndroidSDKTool.avdmanager.executableRelativePath)
            let arguments = ["create", "avd", "-n", name, "-k", image.installIdentifier, "-d", profile.id]
            let activityID = ActivityLog.shared.begin(
                title: "Create \(name)",
                command: ActivityCommand.line(executable: executable, arguments: arguments)
            )
            let result = await self.runner.run(
                executable: executable,
                arguments: arguments,
                environment: AndroidCommandEnvironment(sdkRoot: root).values,
                timeout: .seconds(120)
            )
            await self.load()
            let created = result?.exitCode == 0 && self.devices.contains(where: { $0.name == name })
            var error = result?.standardError ?? "The command could not start."
            if !created, error.isEmpty {
                error = "The device could not be created."
            }
            ActivityLog.shared.finish(
                activityID,
                exitCode: result?.exitCode,
                standardOutput: result?.standardOutput ?? "",
                standardError: created ? "" : error,
                outcome: created ? .succeeded : .failed
            )
            if !created {
                self.installError = "The device could not be created."
            }
            self.creatingName = nil
        }
    }

    func install(_ image: PhoneSystemImage) {
        guard installingImageID == nil, creatingName == nil, let root = SDKLocator.existingRoot() else { return }
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
        devicesLoaded = true
        systemImages = await systemImages(in: root)
        await adoptRunningEmulators(in: root)
        isChecking = false
        hasLoaded = true
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
        guard deletingName == nil, creatingName == nil, !isInstallingImage else { return }
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
            let arguments = ["delete", "avd", "-n", name]
            let activityID = await ActivityLog.shared.begin(
                title: "Delete \(name)",
                command: ActivityCommand.line(executable: executable, arguments: arguments)
            )
            let result = await self.runner.run(
                executable: executable,
                arguments: arguments,
                environment: AndroidCommandEnvironment(sdkRoot: root).values,
                timeout: .seconds(120)
            )
            self.phases[name] = nil
            await self.load()
            let removed = result?.exitCode == 0 && !self.devices.contains(where: { $0.name == name })
            var error = result?.standardError ?? "The command could not start."
            if !removed, error.isEmpty {
                error = "The device could not be deleted."
            }
            await ActivityLog.shared.finish(
                activityID,
                exitCode: result?.exitCode,
                standardOutput: result?.standardOutput ?? "",
                standardError: error,
                outcome: removed ? .succeeded : .failed
            )
            if !removed {
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
