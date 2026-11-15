import SwiftUI

struct SettingsView: View {
    var model: DashboardModel
    var setup: SetupModel
    var paths: PathSettingsModel
    @State private var confirmingRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("SDK location") {
                    LocationRow(
                        setting: paths.sdk,
                        notice: paths.sdkNotice,
                        footnote: model.sdkIsOutsideHome
                            ? "This SDK is outside your home folder, so DroidDesk will not remove it."
                            : "Changing the location does not move or delete anything.",
                        name: "SDK",
                        choose: paths.chooseSDK,
                        reveal: paths.revealSDK,
                        useDefault: paths.useDefaultSDK
                    )
                }

                section("Virtual devices") {
                    LocationRow(
                        setting: paths.avd,
                        notice: paths.avdNotice,
                        footnote: "Existing devices are not moved when the folder changes.",
                        name: "virtual devices",
                        choose: paths.chooseAVD,
                        reveal: paths.revealAVD,
                        useDefault: paths.useDefaultAVD
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Setup")
                        .font(.headline)
                    setupRow
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color(nsColor: .separatorColor))
                        }
                }

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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
        }
    }

    private var setupRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Guided setup")
                Text("Install the SDK and create a virtual device step by step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Run Setup", action: setup.restart)
                .controlSize(.small)
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

/// One folder setting: where it points, where that comes from, and the buttons to change it.
private struct LocationRow: View {
    var setting: PathSetting
    var notice: PathNotice?
    var footnote: String
    var name: String
    var choose: () -> Void
    var reveal: () -> Void
    var useDefault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(setting.display)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Text(setting.exists ? setting.source.label : "\(setting.source.label) · not found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(name) folder")
                Spacer(minLength: 12)
                Button("Choose…", action: choose)
                    .controlSize(.small)
                    .accessibilityLabel("Choose the \(name) folder")
                Button(action: reveal) {
                    Image(systemName: "folder")
                        .frame(width: 16, height: 14)
                }
                .controlSize(.small)
                .disabled(!setting.exists)
                .help("Show in Finder")
                .accessibilityLabel("Show the \(name) folder in Finder")
                if setting.isChosenInApp {
                    Button("Use Default", action: useDefault)
                        .controlSize(.small)
                        .accessibilityLabel("Use the default \(name) folder")
                }
            }
            if let notice {
                Text(notice.text)
                    .font(.callout)
                    .foregroundStyle(notice.isError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
