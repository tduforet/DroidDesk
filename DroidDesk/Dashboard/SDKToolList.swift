import SwiftUI

/// The four SDK tools, in a single bordered group.
struct SDKToolList: View {
    var tools: [SDKToolStatus]
    var updating: AndroidSDKPackage?
    var update: (AndroidSDKTool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                SDKToolRow(status: tool, updating: updating, update: update)
                if index < tools.count - 1 {
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
        .accessibilityLabel("SDK tools")
    }
}

struct SDKToolRow: View {
    var status: SDKToolStatus
    var updating: AndroidSDKPackage?
    var update: (AndroidSDKTool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.tool.displayName)
                if let installed = status.installedVersion {
                    SDKVersionLine(installed: installed, available: status.availableVersion)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)
            if let available = status.availableVersion {
                SDKUpdateControl(
                    toolName: status.tool.displayName,
                    available: available,
                    isUpdating: updating == status.tool.package,
                    isEnabled: updating == nil,
                    action: { update(status.tool) }
                )
            }
            Text(status.statusLabel)
                .foregroundStyle(status.isReady ? Color.green : Color.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct SDKUpdateControl: View {
    var toolName: String
    var available: String
    var isUpdating: Bool
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        if isUpdating {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Updating…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Updating \(toolName)")
        } else {
            Button("Update", action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isEnabled)
                .accessibilityLabel("Update \(toolName) to \(available)")
        }
    }
}

/// Installed revision, then the newer one when Google publishes it: `19.0 → 23.0`.
private struct SDKVersionLine: View {
    var installed: String
    var available: String?

    var body: some View {
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
        .font(.caption.monospaced())
    }
}
