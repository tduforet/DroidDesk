import SwiftUI

struct InstallLocationRequest: Identifiable, Equatable {
    var id = UUID()
    var folder: URL
    var tool: AndroidSDKTool
    var rejection: String?
}

/// Asks where to install sdkmanager and avdmanager. The usual Mac SDK folder is already filled in.
struct InstallLocationSheet: View {
    var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install command-line tools")
                .font(.title2.weight(.semibold))
            Text("sdkmanager and avdmanager will be installed in this folder.")
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 12) {
                Text(SDKPathDisplay.tilde(model.installLocation?.folder ?? SDKLocator.conventionalRoot))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Button("Choose…", action: model.chooseInstallFolder)
            }
            if let rejection = model.installLocation?.rejection {
                Text(rejection)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: model.cancelInstallFolder)
                    .keyboardShortcut(.cancelAction)
                Button("Install", action: model.confirmInstallFolder)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
