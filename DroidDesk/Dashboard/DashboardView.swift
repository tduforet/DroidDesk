import SwiftUI

struct DashboardView: View {
    @State private var model = DashboardModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SDKVerdictView(title: model.title, path: model.path)
                if let tools = model.tools {
                    SDKToolList(tools: tools)
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
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
    private let probe = SDKProbe()

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
        isChecking = true
        inspection = await probe.inspect()
        isChecking = false
    }
}
