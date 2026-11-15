import SwiftUI

/// Replaces the app until an Android SDK, a system image, and a virtual device are in place.
struct SetupView: View {
    var model: SetupModel
    var openVirtualDevices: () -> Void
    var openActivity: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set up Android")
                        .font(.largeTitle.weight(.semibold))
                    Text("DroidDesk installs the official Android SDK and creates a virtual device. No Android Studio needed.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                locationRow
                stepList

                if let failure = model.failure {
                    failureBanner(failure)
                }

                HStack(spacing: 12) {
                    primaryButton
                    if model.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Working")
                    }
                    Spacer()
                    Button("Skip setup", action: model.skip)
                        .buttonStyle(.link)
                        .disabled(!model.canLeave)
                        .help("Use DroidDesk without the guided setup")
                }
            }
            .padding(32)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    private var locationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SDK location")
                .font(.headline)
            HStack(spacing: 12) {
                Text(model.folderLine)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Button("Choose…", action: model.chooseFolder)
                    .disabled(!model.canChooseFolder)
            }
            if let rejection = model.folderRejection {
                Text(rejection)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var stepList: some View {
        VStack(spacing: 0) {
            ForEach(Array(SetupStep.allCases.enumerated()), id: \.element) { index, step in
                stepRow(step)
                if index < SetupStep.allCases.count - 1 {
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
        .accessibilityLabel("Setup steps")
    }

    private func stepRow(_ step: SetupStep) -> some View {
        let state = model.states[step] ?? .pending
        return HStack(spacing: 12) {
            stateMark(state)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                if let detail = detail(for: step) {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityValue(label(for: state))
    }

    @ViewBuilder
    private func stateMark(_ state: SetupStepState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .working:
            ProgressView()
                .controlSize(.small)
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        }
    }

    private func label(for state: SetupStepState) -> String {
        switch state {
        case .done: "Done"
        case .working: "In progress"
        case .pending: "Waiting"
        }
    }

    private func detail(for step: SetupStep) -> String? {
        switch step {
        case .platform: model.plan.map { "API \($0.platform.version)" }
        case .buildTools: model.plan.map { $0.buildTools.version }
        case .systemImage: model.plan.map { $0.image.detail }
        case .device: model.deviceName
        default: nil
        }
    }

    private func failureBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Try again", action: model.retry)
                    .disabled(model.isWorking)
                Button("View activity", action: openActivity)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if model.deviceStage == .ready, !model.installPending {
            VStack(alignment: .leading, spacing: 8) {
                Label("The device is running.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Button(model.primaryTitle, action: openVirtualDevices)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            Button(model.primaryTitle, action: model.primaryAction)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isWorking || model.deviceStage == .starting)
        }
    }
}
