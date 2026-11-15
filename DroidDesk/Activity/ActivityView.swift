import AppKit
import SwiftUI

struct ActivityView: View {
    @State private var log = ActivityLog.shared
    @State private var expandedID: ActivityEntry.ID?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Activity")
                            .font(.title2.weight(.semibold))
                        Text("Downloads, commands, and diagnostics.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button(copied ? "Copied" : "Copy Report", action: copyReport)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Copy diagnostic report")
                }

                if log.entries.isEmpty {
                    Text("No commands yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(log.entries) { entry in
                            entryCard(entry)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Activity")
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .navigationTitle("Activity")
    }

    private func entryCard(_ entry: ActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expandedID = expandedID == entry.id ? nil : entry.id
            } label: {
                entrySummary(entry)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.title), \(entry.outcome.label)")

            if expandedID == entry.id {
                entryDetail(entry)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }

    private func entrySummary(_ entry: ActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if entry.outcome == .running {
                    ProgressView()
                        .controlSize(.small)
                }
                StatusDot(color: entry.outcome.color, label: entry.outcome.label)
            }
            Text(entry.command)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(summaryLine(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryDetail(_ entry: ActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledBlock("Command", entry.command)
            if let exitCode = entry.exitCode {
                Text("Exit \(exitCode)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if entry.standardOutput.isEmpty && entry.standardError.isEmpty && entry.outcome != .running {
                Text("No output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.standardOutput.isEmpty {
                labeledBlock("Output", entry.standardOutput)
            }
            if !entry.standardError.isEmpty {
                labeledBlock("Error", entry.standardError)
            }
        }
        .textSelection(.enabled)
    }

    private func labeledBlock(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryLine(_ entry: ActivityEntry) -> String {
        let time = entry.startedAt.formatted(date: .omitted, time: .shortened)
        return "\(time) · \(entry.outcome.label)"
    }

    private func copyReport() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(log.report(), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

extension ActivityOutcome {
    var color: Color {
        switch self {
        case .running: .orange
        case .succeeded: .green
        case .failed: .red
        case .declined: .orange
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
