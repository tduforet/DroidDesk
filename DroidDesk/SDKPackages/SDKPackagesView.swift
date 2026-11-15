import SwiftUI

struct SDKPackagesView: View {
    var model: PackagesModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Platforms")
                        .font(.title2.weight(.semibold))
                    Text(model.path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("API 36 and newer, including minor versions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                if !model.hasLoaded {
                    SkeletonGroup(rows: 4, label: "Loading platforms")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Build-tools")
                            .font(.headline)
                        SkeletonGroup(rows: 3, label: "Loading build-tools")
                    }
                }
                if !model.platforms.isEmpty {
                    packageGroup(model.platforms)
                        .accessibilityLabel("Platforms")
                }
                if !model.buildTools.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Build-tools")
                            .font(.headline)
                        packageGroup(model.buildTools)
                            .accessibilityLabel("Build-tools")
                    }
                }
                if !model.installed.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Installed")
                            .font(.headline)
                        packageGroup(model.installed)
                    }
                }
                if model.hasLoaded, let note = model.note {
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
        .navigationTitle("SDK Packages")
        .task { await model.refresh() }
        .sheet(isPresented: uninstallSheetPresented) {
            if let package = model.uninstallTarget {
                UninstallPackageSheet(
                    package: package,
                    cancel: model.cancelUninstall,
                    confirm: model.confirmUninstall
                )
            }
        }
    }

    private var uninstallSheetPresented: Binding<Bool> {
        Binding(
            get: { model.uninstallTarget != nil },
            set: { isPresented in
                if !isPresented { model.cancelUninstall() }
            }
        )
    }

    private func packageGroup(_ packages: [StudioPackageStatus]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(packages.enumerated()), id: \.element.id) { index, status in
                packageRow(status)
                if index < packages.count - 1 {
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

    private func packageRow(_ status: StudioPackageStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.package.title)
                HStack(spacing: 6) {
                    StatusDot(
                        color: status.isInstalled ? .green : .red,
                        label: status.isInstalled ? "Ready" : "Missing"
                    )
                    Text(status.package.version)
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospaced())
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            packageAction(status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func packageAction(_ status: StudioPackageStatus) -> some View {
        if model.isInstalling(status.id) {
            PackageProgress(title: "Installing…", label: "Installing \(status.package.title) \(status.package.version)")
        } else if model.isUninstalling(status.id) {
            PackageProgress(title: "Uninstalling…", label: "Uninstalling \(status.package.title) \(status.package.version)")
        } else if !status.isInstalled && model.sdkmanagerReady {
            Button("Install") { model.install(status.package) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isBusy)
                .accessibilityLabel("Install \(status.package.title) \(status.package.version)")
        } else if status.isInstalled && model.sdkmanagerReady {
            Button("Uninstall") { model.requestUninstall(status.package) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .disabled(model.isBusy)
                .accessibilityLabel("Uninstall \(status.package.title) \(status.package.version)")
        }
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

private struct PackageProgress: View {
    var title: String
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// Confirms before one platform or build-tools package is removed. Cancel is the escape action.
private struct UninstallPackageSheet: View {
    var package: StudioPackage
    var cancel: () -> Void
    var confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uninstall \(package.title) \(package.version)?")
                .font(.title2.weight(.semibold))
            Text("This removes it from the SDK. Other packages stay in place.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Uninstall", role: .destructive, action: confirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

@MainActor
@Observable
final class PackagesModel {
    private(set) var root: URL?
    private(set) var platforms: [StudioPackageStatus] = []
    private(set) var buildTools: [StudioPackageStatus] = []
    private(set) var installed: [StudioPackageStatus] = []
    private(set) var uninstallTarget: StudioPackage?
    private(set) var sdkmanagerReady = false
    private(set) var isChecking = false
    private(set) var hasLoaded = false
    private(set) var catalogueFailed = false
    private var packageWork: PackageWork?
    private(set) var workingIdentifier: String?
    private(set) var licensePrompt: SDKLicensePrompt?
    private(set) var failureTitle = "Install failed"
    private(set) var installError: String?
    private var licenseContinuation: CheckedContinuation<Bool, Never>?
    private let runner = CommandRunner()

    var path: String {
        SDKPathDisplay.tilde(root ?? SDKLocator.conventionalRoot)
    }

    var isBusy: Bool { packageWork != nil }

    var note: String? {
        if !sdkmanagerReady { return "Install sdkmanager on the Dashboard first." }
        if catalogueFailed { return "The package list could not be read." }
        return nil
    }

    func isInstalling(_ identifier: String) -> Bool {
        packageWork == .installing && workingIdentifier == identifier
    }

    func isUninstalling(_ identifier: String) -> Bool {
        packageWork == .uninstalling && workingIdentifier == identifier
    }

    func refresh() async {
        guard !isBusy else { return }
        await load()
    }

    func install(_ package: StudioPackage) {
        guard !isBusy, sdkmanagerReady, let root else { return }
        let identifier = package.installIdentifier
        begin(.installing, identifier)
        failureTitle = "Install failed"
        installError = nil
        Task {
            let outcome = await SDKInstaller().installPackages(
                [identifier],
                sdkRoot: root,
                environment: AndroidCommandEnvironment(sdkRoot: root).values
            ) { prompt in
                await self.confirm(prompt)
            }
            switch outcome {
            case .updated:
                await self.load()
                if self.offered.contains(where: { $0.package.installIdentifier == identifier && !$0.isInstalled }) {
                    self.installError = "The package could not be installed."
                }
            case .declined:
                break
            case .failed(let message):
                self.failureTitle = "Install failed"
                self.installError = message
            }
            self.finishWork()
        }
    }

    func requestUninstall(_ package: StudioPackage) {
        guard !isBusy, sdkmanagerReady else { return }
        uninstallTarget = package
    }

    func cancelUninstall() {
        uninstallTarget = nil
    }

    func confirmUninstall() {
        guard !isBusy, sdkmanagerReady, let root, let package = uninstallTarget else { return }
        uninstallTarget = nil
        let identifier = package.installIdentifier
        begin(.uninstalling, identifier)
        failureTitle = "Uninstall failed"
        installError = nil
        Task {
            let outcome = await SDKInstaller().uninstallPackage(
                identifier,
                sdkRoot: root,
                environment: AndroidCommandEnvironment(sdkRoot: root).values
            ) { prompt in
                await self.confirm(prompt)
            }
            switch outcome {
            case .updated:
                await self.load()
                if StudioPackageDisk.isInstalled(package, in: root) {
                    self.installError = "The package could not be uninstalled."
                }
            case .declined:
                break
            case .failed(let message):
                self.failureTitle = "Uninstall failed"
                self.installError = message
            }
            self.finishWork()
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
        catalogueFailed = false
        let located = SDKLocator.existingRoot()
        root = located
        let executable = located?.appending(path: AndroidSDKTool.sdkmanager.executableRelativePath)
        let ready = executable.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false
        sdkmanagerReady = ready
        let onDisk = located.map { StudioPackageDisk.installed(in: $0) } ?? []
        let catalogue = await offeredPackages(executable: ready ? executable : nil, root: located)
        if ready && catalogue == nil {
            catalogueFailed = true
        }
        let offeredPlatforms = catalogue?.platforms ?? []
        let offeredBuildTools = catalogue?.buildTools ?? []
        let offeredIdentifiers = Set((offeredPlatforms + offeredBuildTools).map(\.installIdentifier))
        platforms = offeredPlatforms.map { status(for: $0, root: located) }
        buildTools = offeredBuildTools.map { status(for: $0, root: located) }
        installed = onDisk
            .filter { !offeredIdentifiers.contains($0.installIdentifier) }
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind == .platform }
                return VersionOrdering.isOlder(rhs.version, than: lhs.version)
            }
            .map { StudioPackageStatus(package: $0, isInstalled: true) }
        isChecking = false
        hasLoaded = true
    }

    private var offered: [StudioPackageStatus] {
        platforms + buildTools
    }

    private func status(for package: StudioPackage, root: URL?) -> StudioPackageStatus {
        let present = root.map { StudioPackageDisk.isInstalled(package, in: $0) } ?? false
        return StudioPackageStatus(package: package, isInstalled: present)
    }

    private func offeredPackages(executable: URL?, root: URL?) async -> (platforms: [StudioPackage], buildTools: [StudioPackage])? {
        guard let executable, let root else { return nil }
        guard let result = await runner.run(
            executable: executable,
            arguments: ["--list"],
            environment: AndroidCommandEnvironment(sdkRoot: root).values,
            timeout: .seconds(30)
        ), result.exitCode == 0 else { return nil }
        return (
            StudioPackageCatalogue.offeredPlatforms(in: result.standardOutput),
            StudioPackageCatalogue.offeredBuildTools(in: result.standardOutput)
        )
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

    private func begin(_ work: PackageWork, _ identifier: String) {
        packageWork = work
        workingIdentifier = identifier
    }

    private func finishWork() {
        workingIdentifier = nil
        packageWork = nil
    }
}

private enum PackageWork: Equatable {
    case installing
    case uninstalling
}
