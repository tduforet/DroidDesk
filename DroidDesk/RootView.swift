import SwiftUI

struct RootView: View {
    @Environment(NavigationModel.self) private var navigation
    @State private var dashboard = DashboardModel()
    @State private var packages = PackagesModel()
    @State private var devices = VirtualDevicesModel()
    @State private var setup = SetupModel()
    @State private var paths = PathSettingsModel()

    var body: some View {
        @Bindable var navigation = navigation

        Group {
            if setup.isPresented {
                SetupView(
                    model: setup,
                    openVirtualDevices: {
                        setup.finish()
                        navigation.show(.virtualDevices)
                    },
                    openActivity: {
                        setup.skip()
                        navigation.show(.activity)
                    }
                )
            } else {
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
            }
        }
        .task {
            paths.onChange = {
                Task {
                    await dashboard.refresh()
                    await devices.refresh()
                    await packages.refresh()
                }
            }
        }
        .sheet(isPresented: licenseSheetPresented) {
            if let license = setup.licensePrompt ?? devices.licensePrompt ?? packages.licensePrompt ?? dashboard.licensePrompt {
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
            SettingsView(model: dashboard, setup: setup, paths: paths)
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
        if setup.licensePrompt != nil {
            setup.acceptLicense()
        } else if devices.licensePrompt != nil {
            devices.acceptLicense()
        } else if packages.licensePrompt != nil {
            packages.acceptLicense()
        } else {
            dashboard.acceptLicense()
        }
    }

    private func declineLicense() {
        if setup.licensePrompt != nil {
            setup.declineLicense()
        } else if devices.licensePrompt != nil {
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
                setup.licensePrompt != nil || dashboard.licensePrompt != nil
                    || packages.licensePrompt != nil || devices.licensePrompt != nil
            },
            set: { isPresented in
                if !isPresented {
                    setup.declineLicenseIfNeeded()
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

