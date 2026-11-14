import SwiftUI

struct RootView: View {
    @Environment(NavigationModel.self) private var navigation
    @State private var dashboard = DashboardModel()

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
            switch navigation.section {
            case .dashboard:
                DashboardView(model: dashboard)
            case .virtualDevices, .sdkPackages, .activity, .settings:
                SectionPlaceholder(section: navigation.section)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarRole(.editor)
        .sheet(isPresented: licenseSheetPresented) {
            if let license = dashboard.licensePrompt {
                SDKLicenseSheet(license: license, accept: dashboard.acceptLicense, decline: dashboard.declineLicense)
            }
        }
        .alert(
            "Update failed",
            isPresented: updateErrorPresented
        ) {
            Button("OK", role: .cancel) {
                dashboard.dismissUpdateError()
            }
        } message: {
            Text(dashboard.updateError ?? "")
        }
    }

    private var licenseSheetPresented: Binding<Bool> {
        Binding(
            get: { dashboard.licensePrompt != nil },
            set: { isPresented in
                if !isPresented { dashboard.declineLicenseIfNeeded() }
            }
        )
    }

    private var updateErrorPresented: Binding<Bool> {
        Binding(
            get: { dashboard.updateError != nil },
            set: { isPresented in
                if !isPresented { dashboard.dismissUpdateError() }
            }
        )
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
