import SwiftUI

struct RootView: View {
    @Environment(NavigationModel.self) private var navigation
    @State private var dashboard = DashboardModel()
    @State private var packages = PackagesModel()

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
            case .settings:
                SettingsView(model: dashboard)
            case .sdkPackages:
                SDKPackagesView(model: packages)
            case .virtualDevices, .activity:
                SectionPlaceholder(section: navigation.section)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarRole(.editor)
        .sheet(isPresented: licenseSheetPresented) {
            if let license = packages.licensePrompt ?? dashboard.licensePrompt {
                SDKLicenseSheet(license: license, accept: acceptLicense, decline: declineLicense)
            }
        }
        .alert(
            packages.installError == nil ? dashboard.failureTitle : packages.failureTitle,
            isPresented: updateErrorPresented
        ) {
            Button("OK", role: .cancel) {
                if packages.installError != nil {
                    packages.dismissInstallError()
                } else {
                    dashboard.dismissUpdateError()
                }
            }
        } message: {
            Text(packages.installError ?? dashboard.updateError ?? "")
        }
    }

    private func acceptLicense() {
        if packages.licensePrompt != nil {
            packages.acceptLicense()
        } else {
            dashboard.acceptLicense()
        }
    }

    private func declineLicense() {
        if packages.licensePrompt != nil {
            packages.declineLicense()
        } else {
            dashboard.declineLicense()
        }
    }

    private var licenseSheetPresented: Binding<Bool> {
        Binding(
            get: { dashboard.licensePrompt != nil || packages.licensePrompt != nil },
            set: { isPresented in
                if !isPresented {
                    dashboard.declineLicenseIfNeeded()
                    packages.declineLicenseIfNeeded()
                }
            }
        )
    }

    private var updateErrorPresented: Binding<Bool> {
        Binding(
            get: { dashboard.updateError != nil || packages.installError != nil },
            set: { isPresented in
                if !isPresented {
                    if packages.installError != nil {
                        packages.dismissInstallError()
                    } else {
                        dashboard.dismissUpdateError()
                    }
                }
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
