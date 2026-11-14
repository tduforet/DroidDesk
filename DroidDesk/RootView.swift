import SwiftUI

struct RootView: View {
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation

        NavigationSplitView {
            List(selection: $navigation.section) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
        } detail: {
            SectionPlaceholder(section: navigation.section)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarRole(.editor)
    }
}

private struct SectionPlaceholder: View {
    let section: AppSection

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: section.symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(section.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(section.title)
    }
}
