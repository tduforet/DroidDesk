import SwiftUI

/// Asks before any license is sent to `sdkmanager`. Decline is the cancel action.
struct SDKLicenseSheet: View {
    var license: SDKLicensePrompt
    var accept: () -> Void
    var decline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accept license?")
                .font(.title2.weight(.semibold))
            Text(license.name)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(license.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Decline", role: .cancel, action: decline)
                    .keyboardShortcut(.cancelAction)
                Button("Accept", action: accept)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }
}
