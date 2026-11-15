import Foundation
import Testing
@testable import DroidDesk

struct SDKLocatorTests {
    private let scratch = ScratchFolder()
    private var home: URL { scratch.url }

    @Test func probesTheChosenFolderThenTheEnvironmentThenTheUsualFolder() {
        let chosen = URL(filePath: "/chosen")
        let environment = ["ANDROID_SDK_ROOT": "/from-root", "ANDROID_HOME": "/from-home"]
        let paths = SDKLocator.candidates(environment: environment, configured: chosen, home: home).map(\.path)
        #expect(paths == ["/chosen", "/from-root", "/from-home", home.appending(path: "Library/Android/sdk").path])
    }

    @Test func skipsEmptyEnvironmentVariables() {
        let paths = SDKLocator.candidates(environment: ["ANDROID_SDK_ROOT": "", "ANDROID_HOME": ""], configured: nil, home: home)
        #expect(paths.map(\.path) == [home.appending(path: "Library/Android/sdk").path])
    }

    @Test func picksTheFirstFolderThatExists() {
        let second = scratch.folder("second")
        let root = SDKLocator.existingRoot(
            environment: ["ANDROID_SDK_ROOT": scratch.url.appending(path: "missing").path, "ANDROID_HOME": second.path],
            configured: nil,
            home: home
        )
        #expect(root?.path == second.path)
    }

    @Test func prefersTheFolderChosenInTheApp() {
        let chosen = scratch.folder("chosen")
        let env = scratch.folder("env")
        let root = SDKLocator.existingRoot(environment: ["ANDROID_SDK_ROOT": env.path], configured: chosen, home: home)
        #expect(root?.path == chosen.path)
    }

    @Test func fallsBackToTheUsualFolder() {
        let usual = scratch.folder("Library/Android/sdk")
        #expect(SDKLocator.existingRoot(environment: [:], configured: nil, home: home)?.path == usual.path)
    }

    @Test func findsNothingWhenNoFolderExists() {
        #expect(SDKLocator.existingRoot(environment: [:], configured: nil, home: home) == nil)
    }

    @Test func ignoresAFileWhereAFolderIsExpected() {
        let file = scratch.file("not-a-folder")
        #expect(SDKLocator.existingRoot(environment: ["ANDROID_SDK_ROOT": file.path], configured: nil, home: home) == nil)
    }
}

struct AndroidCommandEnvironmentTests {
    @Test func pointsEveryToolAtTheChosenSDK() {
        let values = AndroidCommandEnvironment(sdkRoot: URL(filePath: "/sdk")).values
        #expect(values["ANDROID_SDK_ROOT"] == "/sdk")
        #expect(values["ANDROID_HOME"] == "/sdk")
    }

    @Test func putsTheSDKToolsFirstOnThePath() throws {
        let path = try #require(AndroidCommandEnvironment(sdkRoot: URL(filePath: "/sdk")).values["PATH"])
        #expect(path.hasPrefix("/sdk/platform-tools:/sdk/emulator:/sdk/cmdline-tools/latest/bin:"))
        #expect(path.count > "/sdk/platform-tools:/sdk/emulator:/sdk/cmdline-tools/latest/bin:".count)
    }
}

struct SDKDiskReaderTests {
    private let scratch = ScratchFolder()

    private func properties(_ revision: String) -> String {
        "Pkg.Revision=\(revision)\nPkg.Desc=Something\n"
    }

    @Test func readsAnInstalledRevision() {
        scratch.file("emulator/source.properties", properties("37.2.13"))
        #expect(InstalledRevision.read(root: scratch.url, tool: .emulator) == "37.2.13")
    }

    @Test func readsNothingWithoutTheFileOrTheKey() {
        #expect(InstalledRevision.read(root: scratch.url, tool: .adb) == nil)
        scratch.file("platform-tools/source.properties", "Pkg.Desc=Only a description\n")
        #expect(InstalledRevision.read(root: scratch.url, tool: .adb) == nil)
        scratch.file("emulator/source.properties", "Pkg.Revision=\n")
        #expect(InstalledRevision.read(root: scratch.url, tool: .emulator) == nil)
    }

    @Test func listsInstalledPlatformsAndBuildTools() {
        scratch.file("platforms/android-37.0/source.properties", properties("2"))
        scratch.file("platforms/android-36/source.properties", properties("2"))
        scratch.file("build-tools/37.0.0/source.properties", properties("37.0.0"))
        let installed = StudioPackageDisk.installed(in: scratch.url)
        #expect(Set(installed.filter { $0.kind == .platform }.map(\.version)) == ["37.0", "36"])
        #expect(installed.filter { $0.kind == .buildTools }.map(\.version) == ["37.0.0"])
    }

    @Test func ignoresHalfInstalledAndExtensionFolders() {
        scratch.folder("platforms/android-35")
        scratch.file("platforms/android-36-ext18/source.properties", properties("1"))
        scratch.file("platforms/notes/source.properties", properties("1"))
        scratch.folder("build-tools/36.0.0")
        #expect(StudioPackageDisk.installed(in: scratch.url).isEmpty)
    }

    @Test func tellsWhetherAPackageIsInstalled() throws {
        scratch.file("platforms/android-37.0/source.properties", properties("2"))
        let platforms = StudioPackageCatalogue.offeredPlatforms(in: Fixture.text("sdkmanager-list-22"))
        let present = try #require(platforms.first { $0.version == "37.0" })
        let absent = try #require(platforms.first { $0.version == "36" })
        #expect(StudioPackageDisk.isInstalled(present, in: scratch.url))
        #expect(!StudioPackageDisk.isInstalled(absent, in: scratch.url))
    }

    @Test func listsInstalledSystemImagesFromAPI36() {
        scratch.folder("system-images/android-37.0/google_apis_playstore/arm64-v8a")
        scratch.folder("system-images/android-35/google_apis_playstore/arm64-v8a")
        scratch.folder("system-images/android-36/google_apis_playstore/x86_64")
        let installed = PhoneSystemImageCatalogue.installed(in: scratch.url)
        // android-35 is below the floor. android-36 has no arm64 image on disk, but the folder check is by API.
        #expect(installed.first?.api == "37.0")
        #expect(!installed.contains { $0.api == "35" })
    }

    @Test func readsAnAVDConfiguration() {
        scratch.file("Pixel.avd/config.ini", "hw.device.name = pixel_9a\n# comment\nhw.lcd.width=1080\n=skipped\nno separator\n")
        let values = AVDConfig.read(directory: scratch.url.appending(path: "Pixel.avd"))
        #expect(values["hw.device.name"] == "pixel_9a")
        #expect(values["hw.lcd.width"] == "1080")
        #expect(values.count == 2)
    }

    @Test func readsNoConfigurationForAMissingFile() {
        #expect(AVDConfig.read(directory: scratch.url.appending(path: "none.avd")).isEmpty)
    }
}

struct CommandLineToolsLayoutTests {
    private let scratch = ScratchFolder()

    private func tools(_ folder: String, revision: String, path: String? = nil) {
        scratch.file("cmdline-tools/\(folder)/bin/sdkmanager", "#!/bin/sh\n", executable: true)
        var text = "Pkg.Revision=\(revision)\n"
        if let path { text += "Pkg.Path=\(path)\n" }
        scratch.file("cmdline-tools/\(folder)/source.properties", text)
    }

    @Test func findsANewerSiblingOfLatest() {
        tools("latest", revision: "19.0", path: "cmdline-tools;19.0")
        tools("latest-2", revision: "20.0")
        #expect(CommandLineToolsLayout.newestRevision(in: scratch.url, newerThan: "19.0") == "20.0")
    }

    @Test func ignoresSiblingsThatAreNotNewerOrCannotRun() {
        tools("latest", revision: "19.0")
        tools("old", revision: "18.0")
        scratch.file("cmdline-tools/broken/source.properties", "Pkg.Revision=99.0\n")
        #expect(CommandLineToolsLayout.newestRevision(in: scratch.url, newerThan: "19.0") == nil)
    }

    @Test func promotesTheNewestSiblingAndKeepsTheOldTools() throws {
        tools("latest", revision: "19.0", path: "cmdline-tools;19.0")
        tools("latest-2", revision: "20.0")
        #expect(try CommandLineToolsLayout.promoteNewest(in: scratch.url))
        let root = scratch.url.appending(path: "cmdline-tools")
        #expect(InstalledRevision.read(directory: root.appending(path: "latest")) == "20.0")
        #expect(InstalledRevision.read(directory: root.appending(path: "19.0")) == "19.0")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "latest-2").path))
    }

    @Test func promotesNothingWhenLatestIsCurrent() throws {
        tools("latest", revision: "20.0")
        #expect(try !CommandLineToolsLayout.promoteNewest(in: scratch.url))
    }
}

struct EmulatorLaunchArgumentsTests {
    private let scratch = ScratchFolder()

    @Test func startModesAddTheirFlag() {
        let root = scratch.url
        let avdHome = scratch.folder("avd")
        #expect(EmulatorLaunchArguments.arguments(avdName: "Pixel", sdkRoot: root, avdHome: avdHome) == ["-avd", "Pixel"])
        #expect(EmulatorLaunchArguments.arguments(avdName: "Pixel", sdkRoot: root, mode: .coldBoot, avdHome: avdHome)
            == ["-avd", "Pixel", "-no-snapshot-load"])
        #expect(EmulatorLaunchArguments.arguments(avdName: "Pixel", sdkRoot: root, mode: .wipeData, avdHome: avdHome)
            == ["-avd", "Pixel", "-wipe-data"])
    }

    @Test func titlesNameTheModeInTheActivityLog() {
        #expect(EmulatorStartMode.normal.activityTitle(for: "Pixel") == "Start Pixel")
        #expect(EmulatorStartMode.coldBoot.activityTitle(for: "Pixel") == "Cold boot Pixel")
        #expect(EmulatorStartMode.wipeData.activityTitle(for: "Pixel") == "Wipe data and start Pixel")
    }

    @Test func fallsBackToAPlainSizeWhenTheSkinIsGone() {
        let avdHome = scratch.folder("avd")
        scratch.file("avd/Pixel.avd/config.ini", "skin.name=pixel_9a\nhw.lcd.width=1080\nhw.lcd.height=2424\n")
        scratch.file("avd/Pixel.ini", "path=\(avdHome.path)/Pixel.avd\n")
        let arguments = EmulatorLaunchArguments.arguments(avdName: "Pixel", sdkRoot: scratch.url, avdHome: avdHome)
        #expect(arguments == ["-avd", "Pixel", "-skin", "1080x2424"])
    }

    @Test func keepsTheSkinWhenItIsInstalled() {
        let avdHome = scratch.folder("avd")
        scratch.file("avd/Pixel.avd/config.ini", "skin.name=pixel_9a\nhw.lcd.width=1080\nhw.lcd.height=2424\n")
        scratch.folder("emulator/skins/pixel_9a")
        let arguments = EmulatorLaunchArguments.arguments(avdName: "Pixel", sdkRoot: scratch.url, avdHome: avdHome)
        #expect(arguments == ["-avd", "Pixel"])
    }

    @Test func keepsASkinThatIsAlreadyASize() {
        let avdHome = scratch.folder("avd")
        scratch.file("avd/Pixel.avd/config.ini", "skin.name=1080x2424\nhw.lcd.width=1080\nhw.lcd.height=2424\n")
        let arguments = EmulatorLaunchArguments.arguments(avdName: "Pixel", sdkRoot: scratch.url, avdHome: avdHome)
        #expect(arguments == ["-avd", "Pixel"])
    }
}

struct VirtualDeviceReaderTests {
    private let scratch = ScratchFolder()

    @Test func describesADeviceFromItsConfiguration() throws {
        let sdkRoot = scratch.folder("sdk")
        scratch.folder("sdk/system-images/android-37.0/google_apis_playstore/arm64-v8a")
        scratch.file("avd/Pixel.avd/config.ini", """
            hw.device.name=pixel_9a
            avd.ini.displayname=Pixel 9a
            image.sysdir.1=system-images/android-37.0/google_apis_playstore/arm64-v8a/
            tag.id=google_apis_playstore
            abi.type=arm64-v8a
            """)
        let entry = AVDListing.Entry(name: "Pixel", path: scratch.url.appending(path: "avd/Pixel.avd").path, device: "pixel_9a (Google)", error: nil)
        let device = VirtualDeviceReader.device(from: entry, sdkRoot: sdkRoot)
        #expect(device.name == "Pixel")
        #expect(device.title == "Pixel 9a")
        #expect(device.detail == "pixel_9a · API 37.0 · Google Play · arm64-v8a")
        #expect(device.readiness == .stopped)
    }

    @Test func flagsADeviceWhoseImageIsNotInstalled() {
        let sdkRoot = scratch.folder("sdk")
        scratch.file("avd/Pixel.avd/config.ini", "image.sysdir.1=system-images/android-37.0/google_apis_playstore/arm64-v8a/\n")
        let entry = AVDListing.Entry(name: "Pixel", path: scratch.url.appending(path: "avd/Pixel.avd").path, device: nil, error: nil)
        #expect(VirtualDeviceReader.device(from: entry, sdkRoot: sdkRoot).readiness == .missingImage)
    }

    @Test func readsTheImageFromAvdmanagersErrorWhenTheConfigurationIsGone() throws {
        let entries = AVDListing.entries(in: Fixture.text("avdmanager-list-avd-missing-image"))
        let broken = try #require(entries.last)
        let device = VirtualDeviceReader.device(from: broken, sdkRoot: scratch.folder("sdk"))
        #expect(device.readiness == .missingImage)
        #expect(device.detail.contains("API 36"))
        #expect(device.detail.contains("arm64-v8a"))
    }
}
