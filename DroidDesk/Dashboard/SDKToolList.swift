import SwiftUI

/// The four SDK tools, in a single bordered group.
struct SDKToolList: View {
    var tools: [SDKToolStatus]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                SDKToolRow(status: tool)
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

    var body: some View {
        HStack(spacing: 12) {
            Text(status.tool.displayName)
            Spacer(minLength: 12)
            Text(status.statusLabel)
                .foregroundStyle(status.isReady ? Color.green : Color.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
