import SwiftUI

struct RootView: View {
    @Environment(NavigationModel.self) private var navigation
    @State private var dashboard = DashboardModel()
    @State private var packages = PackagesModel()
    @State private var devices = VirtualDevicesModel()

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
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarRole(.editor)
        .sheet(isPresented: licenseSheetPresented) {
            if let license = devices.licensePrompt ?? packages.licensePrompt ?? dashboard.licensePrompt {
                SDKLicenseSheet(license: license, accept: acceptLicense, decline: declineLicense)
            }
        }
        .alert(
            failureTitle,
            isPresented: updateErrorPresented
        ) {
            Button("OK", role: .cancel, action: dismissFailure)
        } message: {
            Text(devices.installError ?? packages.installError ?? dashboard.updateError ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section {
        case .dashboard:
            DashboardView(model: dashboard)
        case .settings:
            SettingsView(model: dashboard)
        case .sdkPackages:
            SDKPackagesView(model: packages)
        case .virtualDevices:
            VirtualDevicesView(model: devices)
        case .activity:
            ActivityView()
        }
    }

    private var failureTitle: String {
        if devices.installError != nil { return devices.failureTitle }
        if packages.installError != nil { return packages.failureTitle }
        return dashboard.failureTitle
    }

    private func acceptLicense() {
        if devices.licensePrompt != nil {
            devices.acceptLicense()
        } else if packages.licensePrompt != nil {
            packages.acceptLicense()
        } else {
            dashboard.acceptLicense()
        }
    }

    private func declineLicense() {
        if devices.licensePrompt != nil {
            devices.declineLicense()
        } else if packages.licensePrompt != nil {
            packages.declineLicense()
        } else {
            dashboard.declineLicense()
        }
    }

    private func dismissFailure() {
        if devices.installError != nil {
            devices.dismissInstallError()
        } else if packages.installError != nil {
            packages.dismissInstallError()
        } else {
            dashboard.dismissUpdateError()
        }
    }

    private var licenseSheetPresented: Binding<Bool> {
        Binding(
            get: {
                dashboard.licensePrompt != nil || packages.licensePrompt != nil || devices.licensePrompt != nil
            },
            set: { isPresented in
                if !isPresented {
                    dashboard.declineLicenseIfNeeded()
                    packages.declineLicenseIfNeeded()
                    devices.declineLicenseIfNeeded()
                }
            }
        )
    }

    private var updateErrorPresented: Binding<Bool> {
        Binding(
            get: { dashboard.updateError != nil || packages.installError != nil || devices.installError != nil },
            set: { isPresented in
                if !isPresented { dismissFailure() }
            }
        )
    }
}

