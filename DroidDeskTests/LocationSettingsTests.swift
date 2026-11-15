import Foundation
import Testing
@testable import DroidDesk

struct AVDLocationTests {
    private let scratch = ScratchFolder()
    private var home: URL { scratch.url }

    @Test func prefersTheFolderChosenInTheApp() {
        let chosen = URL(filePath: "/Volumes/Fast/avd")
        let found = AVDLocation.resolved(environment: ["ANDROID_AVD_HOME": "/from-env"], configured: chosen, home: home)
        #expect(found.url.path == "/Volumes/Fast/avd")
        #expect(found.source == .app)
    }

    @Test func thenTheEnvironment() {
        let found = AVDLocation.resolved(environment: ["ANDROID_AVD_HOME": "/from-env"], configured: nil, home: home)
        #expect(found.url.path == "/from-env")
        #expect(found.source == .environment("ANDROID_AVD_HOME"))
    }

    @Test func thenTheAndroidDefault() {
        let found = AVDLocation.resolved(environment: [:], configured: nil, home: home)
        #expect(found.url.path == home.appending(path: ".android/avd").path)
        #expect(found.source == .standard)
    }

    @Test func ignoresAnEmptyEnvironmentVariable() {
        let found = AVDLocation.resolved(environment: ["ANDROID_AVD_HOME": ""], configured: nil, home: home)
        #expect(found.source == .standard)
    }

    @Test func listsDevicesByTheirIniFiles() {
        scratch.file("Pixel_A.ini")
        scratch.file("Pixel_B.ini")
        scratch.folder("Pixel_A.avd")
        scratch.file("notes.txt")
        #expect(AVDLocation.deviceNames(in: home) == ["Pixel_A", "Pixel_B"])
    }

    @Test func listsNothingForAMissingFolder() {
        #expect(AVDLocation.deviceNames(in: home.appending(path: "missing")).isEmpty)
    }
}

struct AVDEnvironmentTests {
    @Test func handsTheChosenFolderToTheTools() {
        let environment = AndroidCommandEnvironment(sdkRoot: URL(filePath: "/sdk"), avdHome: URL(filePath: "/Volumes/Fast/avd"))
        #expect(environment.values["ANDROID_AVD_HOME"] == "/Volumes/Fast/avd")
    }

    @Test func leavesTheToolsOwnDefaultAloneWhenNothingIsChosen() {
        let environment = AndroidCommandEnvironment(sdkRoot: URL(filePath: "/sdk"), avdHome: nil)
        #expect(environment.values["ANDROID_AVD_HOME"] == ProcessInfo.processInfo.environment["ANDROID_AVD_HOME"])
    }
}

struct SDKSourceTests {
    private let scratch = ScratchFolder()
    private var home: URL { scratch.url }

    @Test func reportsTheFolderChosenInTheApp() {
        let chosen = scratch.folder("chosen")
        let found = SDKLocator.resolved(environment: ["ANDROID_SDK_ROOT": "/nope"], configured: chosen, home: home)
        #expect(found?.url.path == chosen.path)
        #expect(found?.source == .app)
    }

    @Test func reportsWhichVariableWasUsed() {
        let folder = scratch.folder("android-home")
        let found = SDKLocator.resolved(environment: ["ANDROID_HOME": folder.path], configured: nil, home: home)
        #expect(found?.source == .environment("ANDROID_HOME"))
    }

    @Test func reportsTheDefaultLocation() {
        scratch.folder("Library/Android/sdk")
        #expect(SDKLocator.resolved(environment: [:], configured: nil, home: home)?.source == .standard)
    }

    @Test func labelsEachSource() {
        #expect(PathSource.app.label == "Chosen in DroidDesk")
        #expect(PathSource.environment("ANDROID_HOME").label == "From ANDROID_HOME")
        #expect(PathSource.standard.label == "Default location")
    }
}

struct SDKFolderRulesTests {
    private let scratch = ScratchFolder()
    private let outside = ScratchFolder()
    private var home: URL { scratch.url }

    @Test func acceptsAnEmptyFolderInsideHomeToInstallInto() {
        let folder = scratch.folder("Developer/android")
        #expect(SDKFolderRules.verdict(folder, home: home) == .install)
    }

    @Test func acceptsAnSDKInsideHome() {
        let folder = scratch.folder("Developer/android")
        scratch.folder("Developer/android/platform-tools")
        #expect(SDKFolderRules.verdict(folder, home: home) == .install)
    }

    @Test func acceptsAnExistingSDKOutsideHomeAndKeepsItInPlace() {
        outside.folder("platform-tools")
        #expect(SDKFolderRules.verdict(outside.url, home: home) == .existing)
    }

    @Test func refusesAFolderOutsideHomeThatIsNotAnSDK() {
        outside.file("photo.jpg")
        #expect(SDKFolderRules.verdict(outside.url, home: home) == .rejected(SDKFolderRules.rejection))
    }

    @Test func refusesHomeEvenWhenItLooksLikeAnSDK() {
        scratch.folder("emulator")
        #expect(SDKFolderRules.verdict(home, home: home) == .rejected(SDKFolderRules.rejection))
    }

    @Test func refusesTheRootOfTheDisk() {
        #expect(SDKFolderRules.verdict(URL(filePath: "/"), home: home) == .rejected(SDKFolderRules.rejection))
    }

    @Test(arguments: ["Documents", "Library", "Library/Android", ".android"])
    func refusesProtectedFoldersEvenWithAnSDKInside(name: String) {
        scratch.folder("\(name)/emulator")
        #expect(SDKFolderRules.verdict(home.appending(path: name), home: home) == .rejected(SDKFolderRules.rejection))
    }

    @Test func acceptsTheUsualSDKFolderUnderLibrary() {
        let sdk = scratch.folder("Library/Android/sdk")
        #expect(SDKFolderRules.verdict(sdk, home: home) == .install)
    }

    @Test func refusesAFile() {
        let file = scratch.file("notes.txt")
        #expect(SDKFolderRules.verdict(file, home: home) == .rejected("That is a file, not a folder."))
    }

    @Test func judgesAShortcutByWhereItPoints() throws {
        outside.folder("emulator")
        let link = home.appending(path: "sdk")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.url)
        // The target is an SDK outside home: usable, and never removed.
        #expect(SDKFolderRules.verdict(link, home: home) == .existing)
    }

    @Test func refusesAShortcutToAProtectedFolder() throws {
        scratch.folder("Documents/emulator")
        let link = home.appending(path: "sdk")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.appending(path: "Documents"))
        #expect(SDKFolderRules.verdict(link, home: home) == .rejected(SDKFolderRules.rejection))
    }

    @Test func refusesAShortcutToAFolderThatIsNotAnSDK() throws {
        let link = home.appending(path: "sdk")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.url)
        #expect(SDKFolderRules.verdict(link, home: home) == .rejected(SDKFolderRules.rejection))
    }
}

struct AVDFolderRulesTests {
    private let scratch = ScratchFolder()
    private var home: URL { scratch.url }

    @Test func acceptsAWritableFolder() {
        #expect(AVDFolderRules.verdict(scratch.folder("avd"), home: home) == .accepted)
    }

    @Test func acceptsAFolderOutsideHome() {
        let other = ScratchFolder()
        #expect(AVDFolderRules.verdict(other.url, home: home) == .accepted)
    }

    @Test func refusesAFolderThatDoesNotExist() {
        #expect(AVDFolderRules.verdict(home.appending(path: "missing"), home: home) == .rejected("That is not a folder."))
    }

    @Test func refusesAFile() {
        #expect(AVDFolderRules.verdict(scratch.file("avd"), home: home) == .rejected("That is not a folder."))
    }

    @Test func refusesTheHomeFolderAndTheDiskRoot() {
        #expect(AVDFolderRules.verdict(home, home: home) != .accepted)
        #expect(AVDFolderRules.verdict(URL(filePath: "/"), home: home) != .accepted)
    }

    @Test func refusesAFolderItCannotWriteIn() throws {
        let folder = scratch.folder("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        #expect(AVDFolderRules.verdict(folder, home: home) == .rejected("DroidDesk cannot write in that folder."))
    }
}
