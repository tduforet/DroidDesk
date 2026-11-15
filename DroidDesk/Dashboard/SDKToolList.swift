import SwiftUI

/// Managers share one package, so they sit on one line. adb and emulator stay in their own group below.
struct SDKToolList: View {
    var tools: [SDKToolStatus]
    var updating: AndroidSDKPackage?
    var installing: [AndroidSDKTool]
    var installStatus: String?
    var update: (AndroidSDKTool) -> Void
    var install: (AndroidSDKTool) -> Void

    private var isBusy: Bool { updating != nil || !installing.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sdkmanager = status(for: .sdkmanager), let avdmanager = status(for: .avdmanager) {
                toolGroup {
                    SDKCommandLineToolsRow(
                        sdkmanager: sdkmanager,
                        avdmanager: avdmanager,
                        updating: updating,
                        installing: installing,
                        installStatus: installStatus,
                        isBusy: isBusy,
                        update: update,
                        install: install
                    )
                }
            }
            let devices = tools.filter { $0.tool == .adb || $0.tool == .emulator }
            if !devices.isEmpty {
                toolGroup {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, tool in
                        SDKToolRow(
                            status: tool,
                            updating: updating,
                            installing: installing,
                            installStatus: installStatus,
                            isBusy: isBusy,
                            update: update,
                            install: install
                        )
                        if index < devices.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SDK tools")
    }

    private func status(for tool: AndroidSDKTool) -> SDKToolStatus? {
        tools.first { $0.tool == tool }
    }

    private func toolGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }
}

/// sdkmanager and avdmanager come from the same package, so they share one version and one action.
private struct SDKCommandLineToolsRow: View {
    var sdkmanager: SDKToolStatus
    var avdmanager: SDKToolStatus
    var updating: AndroidSDKPackage?
    var installing: [AndroidSDKTool]
    var installStatus: String?
    var isBusy: Bool
    var update: (AndroidSDKTool) -> Void
    var install: (AndroidSDKTool) -> Void

    private var managers: [SDKToolStatus] { [sdkmanager, avdmanager] }

    private var versionStatus: SDKToolStatus {
        sdkmanager.installedVersion != nil ? sdkmanager : avdmanager
    }

    private var isWorking: Bool {
        updating == .commandLineTools || installing.contains(.sdkmanager) || installing.contains(.avdmanager)
    }

    private var readinessAgrees: Bool { sdkmanager.isReady == avdmanager.isReady }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 16) {
                    ForEach(managers) { status in
                        HStack(spacing: 6) {
                            Text(status.tool.displayName)
                            if !readinessAgrees, !status.isReady {
                                StatusDot(color: .red, label: "Missing")
                            }
                        }
                    }
                }
                if versionStatus.installedVersion != nil || (readinessAgrees && !sdkmanager.isReady) {
                    SDKVersionLine(
                        installed: versionStatus.installedVersion,
                        available: versionStatus.availableVersion,
                        isReady: versionStatus.isReady
                    )
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("sdkmanager and avdmanager")

            Spacer(minLength: 12)
            if let available = versionStatus.availableVersion {
                SDKRowAction(
                    title: "Update",
                    workingTitle: "Updating…",
                    accessibilityLabel: "Update sdkmanager and avdmanager to \(available)",
                    isWorking: isWorking,
                    isEnabled: !isBusy,
                    action: { update(versionStatus.tool) }
                )
            } else if !sdkmanager.isReady {
                SDKRowAction(
                    title: "Install",
                    workingTitle: installStatus ?? "Installing…",
                    accessibilityLabel: "Install sdkmanager and avdmanager",
                    isWorking: isWorking,
                    isEnabled: !isBusy,
                    action: { install(.sdkmanager) }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

struct SDKToolRow: View {
    var status: SDKToolStatus
    var updating: AndroidSDKPackage?
    var installing: [AndroidSDKTool]
    var installStatus: String?
    var isBusy: Bool
    var update: (AndroidSDKTool) -> Void
    var install: (AndroidSDKTool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.tool.displayName)
                if status.installedVersion != nil || !status.isReady {
                    SDKVersionLine(
                        installed: status.installedVersion,
                        available: status.availableVersion,
                        isReady: status.isReady
                    )
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)
            if let available = status.availableVersion {
                SDKRowAction(
                    title: "Update",
                    workingTitle: "Updating…",
                    accessibilityLabel: "Update \(status.tool.displayName) to \(available)",
                    isWorking: updating == status.tool.package,
                    isEnabled: !isBusy,
                    action: { update(status.tool) }
                )
            } else if !status.isReady {
                SDKRowAction(
                    title: "Install",
                    workingTitle: installStatus ?? "Installing…",
                    accessibilityLabel: "Install \(status.tool.displayName)",
                    isWorking: installing.contains(status.tool),
                    isEnabled: !isBusy,
                    action: { install(status.tool) }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct SDKRowAction: View {
    var title: String
    var workingTitle: String
    var accessibilityLabel: String
    var isWorking: Bool
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        if isWorking {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(workingTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isEnabled)
                .accessibilityLabel(accessibilityLabel)
        }
    }
}

/// Installed revision, then the newer one when Google publishes it: `19.0 → 23.0`.
/// A missing tool has no revision, so the line is only the red dot.
private struct SDKVersionLine: View {
    var installed: String?
    var available: String?
    var isReady: Bool

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(color: isReady ? .green : .red, label: isReady ? "Ready" : "Missing")
            if let installed {
                HStack(spacing: 0) {
                    Text(installed)
                        .foregroundStyle(.secondary)
                    if let available {
                        Text(" → ")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("to")
                        Text(available)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .font(.caption.monospaced())
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
