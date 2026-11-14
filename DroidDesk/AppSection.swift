import SwiftUI

/// Sidebar destinations from the product brief. Order is the navigation order.
enum AppSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case dashboard
    case virtualDevices
    case sdkPackages
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .virtualDevices: "Virtual Devices"
        case .sdkPackages: "SDK Packages"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var summary: String {
        switch self {
        case .dashboard:
            "SDK health and quick setup."
        case .virtualDevices:
            "Create and control Android virtual devices."
        case .sdkPackages:
            "Install and update required components."
        case .activity:
            "Downloads, commands, and diagnostics."
        case .settings:
            "SDK path, defaults, and advanced options."
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .virtualDevices: "iphone"
        case .sdkPackages: "square.stack.3d.up"
        case .activity: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }

    /// Sections reached from the View menu. Settings stays on the application menu.
    var viewMenuShortcut: KeyEquivalent? {
        switch self {
        case .dashboard: "1"
        case .virtualDevices: "2"
        case .sdkPackages: "3"
        case .activity: "4"
        case .settings: nil
        }
    }
}
