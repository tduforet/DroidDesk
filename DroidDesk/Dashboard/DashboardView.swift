import SwiftUI

struct DashboardView: View {
    var model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.tools == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBar(width: 260, height: 22)
                        SkeletonBar(width: 340, height: 12)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Checking the SDK")
                    SkeletonGroup(rows: 1, label: "Loading command-line tools")
                    SkeletonGroup(rows: 2, label: "Loading adb and emulator")
                } else {
                    SDKVerdictView(title: model.title, path: model.path)
                }
                if let tools = model.tools {
                    SDKToolList(
                        tools: tools,
                        updating: model.updatingPackage,
                        installing: model.installingTools,
                        installStatus: model.installStatus,
                        update: model.update,
                        install: model.install
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .navigationTitle("Dashboard")
        .task { await model.refresh() }
        .sheet(isPresented: Binding(
            get: { model.installLocation != nil },
            set: { isPresented in
                if !isPresented { model.cancelInstallFolder() }
            }
        )) {
            InstallLocationSheet(model: model)
        }
    }
}

@MainActor
@Observable
final class DashboardModel {
    private(set) var inspection: SDKInspection?
    private(set) var isChecking = false
    private(set) var updatingPackage: AndroidSDKPackage?
    private(set) var installingTools: [AndroidSDKTool] = []
    private(set) var installStatus: String?
    private(set) var isRemovingSDK = false
    private(set) var installLocation: InstallLocationRequest?
    private(set) var licensePrompt: SDKLicensePrompt?
    private(set) var failureTitle = "Update failed"
    private(set) var updateError: String?
    private let probe = SDKProbe()
    private var licenseContinuation: CheckedContinuation<Bool, Never>?

    var title: String {
        inspection?.title ?? ""
    }

    var path: String? {
        inspection?.pathLine
    }

    var tools: [SDKToolStatus]? {
        inspection?.tools
    }

    var canRemoveSDK: Bool {
        inspection?.root != nil && !isBusy
    }

    private var isBusy: Bool {
        updatingPackage != nil || !installingTools.isEmpty || isRemovingSDK
    }

    func refresh() async {
        guard !isBusy else { return }
        await reload()
    }

    func update(_ tool: AndroidSDKTool) {
        guard !isBusy, let root = inspection?.root else { return }
        guard let available = inspection?.tools.first(where: { $0.tool == tool })?.availableVersion else { return }
        let package = tool.package
        updatingPackage = package
        failureTitle = "Update failed"
        updateError = nil
        Task {
            let outcome = await SDKInstaller().install(
                package: package,
                availableVersion: available,
                sdkRoot: root,
                environment: AndroidCommandEnvironment(sdkRoot: root).values
            ) { prompt in
                await self.confirm(prompt)
            }
            switch outcome {
            case .updated:
                await self.reload()
            case .declined:
                break
            case .failed(let message):
                self.updateError = message
            }
            self.updatingPackage = nil
        }
    }

    func install(_ tool: AndroidSDKTool) {
        guard !isBusy, installLocation == nil else { return }
        let managersReady = inspection?.tools.contains { $0.tool == .sdkmanager && $0.isReady } == true
        if !managersReady {
            installLocation = InstallLocationRequest(
                folder: SDKLocationStore.url ?? SDKLocator.conventionalRoot,
                tool: tool
            )
            return
        }
        let root = inspection?.root ?? SDKLocationStore.url ?? SDKLocator.conventionalRoot
        startInstall(tool, into: root)
    }

    func chooseInstallFolder() {
        guard var request = installLocation else { return }
        switch SDKFolderPicker.choose(startingAt: request.folder) {
        case .cancelled:
            return
        case .rejected:
            request.rejection = SDKInstallLocation.rejectionMessage
        case .selected(let folder):
            request.folder = folder
            request.rejection = nil
        }
        installLocation = request
    }

    func confirmInstallFolder() {
        guard let request = installLocation else { return }
        guard let folder = SDKInstallLocation.accepted(request.folder) else {
            var request = request
            request.rejection = SDKInstallLocation.rejectionMessage
            installLocation = request
            return
        }
        installLocation = nil
        SDKLocationStore.save(folder)
        startInstall(request.tool, into: folder)
    }

    func cancelInstallFolder() {
        installLocation = nil
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

    func dismissUpdateError() {
        updateError = nil
    }

    func removeSDK() {
        guard canRemoveSDK, let root = inspection?.root else { return }
        isRemovingSDK = true
        failureTitle = "Remove failed"
        updateError = nil
        Task {
            let outcome = await SDKRemover.remove(root)
            if case .removed = outcome {
                SDKLocationStore.clear()
            } else if case .failed(let message) = outcome {
                self.failureTitle = "Remove failed"
                self.updateError = message
            }
            await self.reload()
            self.isRemovingSDK = false
        }
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

    private func startInstall(_ tool: AndroidSDKTool, into root: URL) {
        updateError = nil
        Task {
            let outcome = await bootstrap(tool, into: root)
            switch outcome {
            case .updated:
                await self.reload()
            case .declined:
                break
            case .failed(let message):
                self.failureTitle = "Install failed"
                self.updateError = message
            }
            self.installingTools = []
            self.installStatus = nil
        }
    }

    private func bootstrap(_ tool: AndroidSDKTool, into root: URL) async -> SDKInstallOutcome {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            return .failed("The SDK folder could not be created.")
        }

        let sdkmanagerReady = inspection?.root == root
            && inspection?.tools.contains { $0.tool == .sdkmanager && $0.isReady } == true
        if !sdkmanagerReady {
            installingTools = [.sdkmanager, .avdmanager]
            installStatus = "Downloading…"
            let downloaded = await CommandLineToolsBootstrap().install(into: root)
            guard case .updated = downloaded else { return downloaded }
            await reload()
            let ready = inspection?.tools.contains { $0.tool == .sdkmanager && $0.isReady } == true
            guard ready else { return .failed("sdkmanager could not be started.") }
            if tool.package == .commandLineTools { return .updated }
        }

        guard tool.package != .commandLineTools else { return .updated }
        let stillMissing = inspection?.tools.contains { $0.tool == tool && !$0.isReady } == true
        guard stillMissing else { return .updated }

        installingTools = [tool]
        installStatus = "Installing…"
        return await SDKInstaller().installPackages(
            [tool.package.installIdentifier],
            sdkRoot: root,
            environment: AndroidCommandEnvironment(sdkRoot: root).values
        ) { prompt in
            await self.confirm(prompt)
        }
    }

    private func reload() async {
        isChecking = true
        inspection = await probe.inspect()
        isChecking = false
    }
}
