import Foundation
import Testing
@testable import DroidDesk

/// Every test runs against a scratch folder standing in for the user's home, never the real one.
struct SDKInstallLocationTests {
    private let scratch = ScratchFolder()
    private var home: URL { scratch.url }

    @Test func acceptsTheUsualSDKFolder() {
        let sdk = SDKLocator.conventionalRoot(home: home)
        #expect(SDKInstallLocation.accepted(sdk, home: home) != nil)
    }

    @Test func acceptsAFolderThatDoesNotExistYet() {
        #expect(SDKInstallLocation.accepted(home.appending(path: "Developer/android-sdk"), home: home) != nil)
    }

    @Test func acceptsAnExistingFolder() {
        let folder = scratch.folder("tools/sdk")
        #expect(SDKInstallLocation.accepted(folder, home: home) != nil)
    }

    @Test func refusesTheHomeFolderItself() {
        #expect(SDKInstallLocation.accepted(home, home: home) == nil)
    }

    @Test(arguments: ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public",
                      "Applications", "Library", "Library/Android", ".android"])
    func refusesTheFoldersMacOSAndAndroidKeepForThemselves(name: String) {
        scratch.folder(name)
        #expect(SDKInstallLocation.accepted(home.appending(path: name), home: home) == nil)
    }

    @Test func refusesFoldersOutsideHome() {
        #expect(SDKInstallLocation.accepted(URL(filePath: "/tmp/sdk"), home: home) == nil)
        #expect(SDKInstallLocation.accepted(URL(filePath: "/"), home: home) == nil)
        #expect(SDKInstallLocation.accepted(URL(filePath: "/Applications"), home: home) == nil)
    }

    @Test func refusesASiblingWhoseNameStartsWithHome() {
        let sibling = URL(filePath: home.path + "-other/sdk")
        #expect(SDKInstallLocation.accepted(sibling, home: home) == nil)
    }

    @Test func refusesAPlainFile() {
        let file = scratch.file("notes.txt", "hello")
        #expect(SDKInstallLocation.accepted(file, home: home) == nil)
    }

    @Test func refusesAShortcutToAProtectedFolder() throws {
        scratch.folder("Documents")
        let link = home.appending(path: "sdk")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.appending(path: "Documents"))
        #expect(SDKInstallLocation.accepted(link, home: home) == nil)
    }

    @Test func refusesAShortcutToAFolderOutsideHome() throws {
        let outside = ScratchFolder()
        let link = home.appending(path: "sdk")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.url)
        #expect(SDKInstallLocation.accepted(link, home: home) == nil)
    }

    @Test func refusesAFolderReachedThroughDotDot() {
        let tricky = home.appending(path: "a/../../elsewhere")
        #expect(SDKInstallLocation.accepted(tricky, home: home) == nil)
    }
}

struct SDKRemoverTests {
    private let scratch = ScratchFolder()
    private var home: URL { scratch.url }

    private func expectRefused(_ outcome: SDKRemover.Outcome, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .failed(let message) = outcome else {
            Issue.record("The folder should have been refused.", sourceLocation: sourceLocation)
            return
        }
        #expect(message.contains("not an Android SDK"), sourceLocation: sourceLocation)
    }

    @Test func removesAFolderThatLooksLikeAnSDK() {
        let sdk = scratch.folder("Developer/sdk")
        scratch.folder("Developer/sdk/platform-tools")
        scratch.file("Developer/sdk/platform-tools/adb")
        guard case .removed = SDKRemover.removeNow(sdk, home: home, configured: nil) else {
            Issue.record("The SDK should have been removed.")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: sdk.path))
    }

    @Test func removesTheUsualSDKFolderEvenWhenEmpty() {
        let sdk = scratch.folder("Library/Android/sdk")
        guard case .removed = SDKRemover.removeNow(sdk, home: home, configured: nil) else {
            Issue.record("The usual folder should have been removed.")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: sdk.path))
        #expect(FileManager.default.fileExists(atPath: home.appending(path: "Library/Android").path))
    }

    @Test func removesTheFolderChosenInTheAppEvenWhenEmpty() {
        let sdk = scratch.folder("Developer/chosen")
        guard case .removed = SDKRemover.removeNow(sdk, home: home, configured: sdk) else {
            Issue.record("The chosen folder should have been removed.")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: sdk.path))
    }

    @Test func refusesAFolderWithoutAnySDKContent() {
        let folder = scratch.folder("Developer/photos")
        scratch.file("Developer/photos/cat.jpg")
        expectRefused(SDKRemover.removeNow(folder, home: home, configured: nil))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "cat.jpg").path))
    }

    @Test(arguments: ["Desktop", "Documents", "Library", "Library/Android", ".android"])
    func refusesProtectedFoldersEvenWithAnSDKMarkerInside(name: String) {
        let folder = scratch.folder(name)
        scratch.folder("\(name)/emulator")
        expectRefused(SDKRemover.removeNow(folder, home: home, configured: nil))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "emulator").path))
    }

    @Test func refusesTheHomeFolderEvenWithAnSDKMarkerInside() {
        scratch.folder("platforms")
        expectRefused(SDKRemover.removeNow(home, home: home, configured: nil))
        #expect(FileManager.default.fileExists(atPath: home.appending(path: "platforms").path))
    }

    @Test func refusesAFolderOutsideHome() {
        let outside = ScratchFolder()
        outside.folder("emulator")
        expectRefused(SDKRemover.removeNow(outside.url, home: home, configured: nil))
        #expect(FileManager.default.fileExists(atPath: outside.url.appending(path: "emulator").path))
    }

    @Test func refusesTheRootOfTheDisk() {
        expectRefused(SDKRemover.removeNow(URL(filePath: "/"), home: home, configured: nil))
    }

    @Test func leavesAShortcutAndItsTargetInPlace() throws {
        let target = scratch.folder("Developer/real-sdk")
        scratch.folder("Developer/real-sdk/emulator")
        let link = home.appending(path: "Developer/sdk-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        guard case .failed(let message) = SDKRemover.removeNow(link, home: home, configured: nil) else {
            Issue.record("A shortcut should not be removed.")
            return
        }
        #expect(message.contains("shortcut"))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "emulator").path))
    }

    @Test func reportsAFolderThatIsAlreadyGone() {
        let missing = home.appending(path: "Developer/gone")
        guard case .failed(let message) = SDKRemover.removeNow(missing, home: home, configured: nil) else {
            Issue.record("A missing folder cannot be removed.")
            return
        }
        #expect(message.contains("already gone"))
    }

    @Test func neverTouchesTheAVDFolder() {
        let sdk = scratch.folder("Library/Android/sdk")
        let avd = scratch.folder(".android/avd/Pixel.avd")
        _ = SDKRemover.removeNow(sdk, home: home, configured: nil)
        #expect(FileManager.default.fileExists(atPath: avd.path))
    }
}
