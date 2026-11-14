import SwiftUI

struct DashboardView: View {
    var model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SDKVerdictView(title: model.title, path: model.path)
                if let tools = model.tools {
                    SDKToolList(tools: tools, updating: model.updatingPackage) { tool in
                        model.update(tool)
                    }
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
    }
}

@MainActor
@Observable
final class DashboardModel {
    private(set) var inspection: SDKInspection?
    private(set) var isChecking = false
    private(set) var updatingPackage: AndroidSDKPackage?
    private(set) var licensePrompt: SDKLicensePrompt?
    private(set) var updateError: String?
    private let probe = SDKProbe()
    private var licenseContinuation: CheckedContinuation<Bool, Never>?

    var title: String {
        if isChecking, inspection == nil { return "Checking the SDK…" }
        return inspection?.title ?? "Checking the SDK…"
    }

    var path: String? {
        inspection?.pathLine
    }

    var tools: [SDKToolStatus]? {
        inspection?.tools
    }

    func refresh() async {
        guard updatingPackage == nil else { return }
        await reload()
    }

    func update(_ tool: AndroidSDKTool) {
        guard updatingPackage == nil, let root = inspection?.root else { return }
        guard let available = inspection?.tools.first(where: { $0.tool == tool })?.availableVersion else { return }
        let package = tool.package
        updatingPackage = package
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

    private func reload() async {
        isChecking = true
        inspection = await probe.inspect()
        isChecking = false
    }
}
