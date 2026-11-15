import SwiftUI

struct SettingsView: View {
    var model: DashboardModel
    @State private var confirmingRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SDK location")
                        .font(.title2.weight(.semibold))
                    Text(model.path ?? SDKPathDisplay.tilde(SDKLocator.conventionalRoot))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Advanced")
                        .font(.headline)
                    removalRow
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color(nsColor: .separatorColor))
                        }
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .navigationTitle("Settings")
        .task { await model.refresh() }
        .sheet(isPresented: $confirmingRemoval) {
            RemoveSDKSheet(
                path: model.path ?? SDKPathDisplay.tilde(SDKLocator.conventionalRoot),
                cancel: { confirmingRemoval = false },
                confirm: {
                    confirmingRemoval = false
                    model.removeSDK()
                }
            )
        }
    }

    private var removalRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Remove SDK")
                Text("Delete the SDK folder. Virtual devices in ~/.android stay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if model.isRemovingSDK {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Removing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Removing the SDK")
            } else {
                Button {
                    confirmingRemoval = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
                .disabled(!model.canRemoveSDK)
                .accessibilityLabel("Remove the Android SDK")
            }
        }
    }
}

/// Confirms before the SDK folder is deleted. Cancel is the escape action.
private struct RemoveSDKSheet: View {
    var path: String
    var cancel: () -> Void
    var confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remove the Android SDK?")
                .font(.title2.weight(.semibold))
            Text("This permanently deletes \(path), including command-line tools, platform-tools, the emulator, platforms, and system images.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Virtual devices in ~/.android are left in place.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Remove SDK", role: .destructive, action: confirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
