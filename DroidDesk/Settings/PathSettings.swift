import AppKit
import Foundation
import Observation

/// A folder setting as the Settings screen shows it.
struct PathSetting: Equatable {
    var url: URL
    var source: PathSource
    var exists: Bool

    var display: String { SDKPathDisplay.tilde(url) }
    var isChosenInApp: Bool { source == .app }
}

struct PathNotice: Equatable {
    var text: String
    var isError: Bool
}

/// Reads and changes where DroidDesk finds the SDK and keeps virtual devices. Nothing is moved or deleted.
@MainActor
@Observable
final class PathSettingsModel {
    private(set) var sdkNotice: PathNotice?
    private(set) var avdNotice: PathNotice?
    /// Bumped after every change so views read the folders again.
    private var revision = 0

    /// Called after a folder changes, so the Dashboard and Virtual Devices read the new one.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    var sdk: PathSetting {
        _ = revision
        if let found = SDKLocator.resolved() {
            return PathSetting(url: found.url, source: found.source, exists: true)
        }
        let chosen = SDKLocationStore.url
        return PathSetting(
            url: chosen ?? SDKLocator.conventionalRoot,
            source: chosen == nil ? .standard : .app,
            exists: false
        )
    }

    var avd: PathSetting {
        _ = revision
        let found = AVDLocation.resolved()
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: found.url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        return PathSetting(url: found.url, source: found.source, exists: exists)
    }

    // MARK: SDK

    func chooseSDK() {
        guard let picked = SDKFolderPicker.pick(
            message: "Choose an existing Android SDK, or a folder in your home directory to install one in.",
            startingAt: sdk.url
        ) else { return }
        switch SDKFolderRules.verdict(picked) {
        case .rejected(let message):
            sdkNotice = PathNotice(text: message, isError: true)
        case .install:
            SDKLocationStore.save(picked)
            sdkNotice = PathNotice(
                text: SDKPathRules.containsSDKMarker(picked)
                    ? "Using the SDK in \(SDKPathDisplay.tilde(picked))."
                    : "No SDK in this folder yet. Install it from the Dashboard.",
                isError: false
            )
            changed()
        case .existing:
            SDKLocationStore.save(picked)
            sdkNotice = PathNotice(
                text: "Using the SDK in \(SDKPathDisplay.tilde(picked)). DroidDesk will not remove an SDK outside your home folder.",
                isError: false
            )
            changed()
        }
    }

    func useDefaultSDK() {
        SDKLocationStore.clear()
        sdkNotice = PathNotice(text: "Using the default location again. The previous folder was left in place.", isError: false)
        changed()
    }

    func revealSDK() {
        reveal(sdk)
    }

    // MARK: Virtual devices

    func chooseAVD() {
        let previous = avd.url
        guard let picked = SDKFolderPicker.pick(
            message: "Choose the folder where virtual devices are stored.",
            startingAt: previous
        ) else { return }
        if case .rejected(let message) = AVDFolderRules.verdict(picked) {
            avdNotice = PathNotice(text: message, isError: true)
            return
        }
        AVDLocationStore.save(picked)
        avdNotice = movedNotice(from: previous, to: picked)
        changed()
    }

    func useDefaultAVD() {
        let previous = avd.url
        AVDLocationStore.clear()
        avdNotice = movedNotice(from: previous, to: avd.url)
        changed()
    }

    func revealAVD() {
        reveal(avd)
    }

    // MARK: Helpers

    /// Devices stay where they are, so say how many will no longer be listed.
    private func movedNotice(from previous: URL, to next: URL) -> PathNotice {
        guard previous.standardizedFileURL.path != next.standardizedFileURL.path else {
            return PathNotice(text: "Virtual devices are stored in \(SDKPathDisplay.tilde(next)).", isError: false)
        }
        let left = AVDLocation.deviceNames(in: previous).count
        if left == 0 {
            return PathNotice(text: "Virtual devices are stored in \(SDKPathDisplay.tilde(next)).", isError: false)
        }
        let noun = left == 1 ? "device stays" : "devices stay"
        return PathNotice(
            text: "\(left) \(noun) in \(SDKPathDisplay.tilde(previous)) and won't be listed here. Existing devices are not moved.",
            isError: false
        )
    }

    private func reveal(_ setting: PathSetting) {
        guard setting.exists else { return }
        NSWorkspace.shared.activateFileViewerSelecting([setting.url])
    }

    private func changed() {
        revision += 1
        onChange?()
    }
}
