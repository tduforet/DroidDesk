import Testing
@testable import DroidDesk

struct SDKRepositoryListingParserTests {
    @Test func readsAvailableUpdatesTable() {
        let listing = SDKRepositoryListingParser.parse(Fixture.text("sdkmanager-list-newer-22"))
        #expect(listing.updates["emulator"] == "37.2.13")
        #expect(listing.updates["platform-tools"] == "37.0.1")
        #expect(listing.updates["cmdline-tools;latest"] == "20.0")
    }

    @Test func mapsUpdatesToTools() {
        let listing = SDKRepositoryListingParser.parse(Fixture.text("sdkmanager-list-newer-22"))
        #expect(listing.availableVersion(for: .emulator, installed: "36.1.9") == "37.2.13")
        #expect(listing.availableVersion(for: .adb, installed: "36.0.0") == "37.0.1")
        #expect(listing.availableVersion(for: .sdkmanager, installed: "19.0") == "20.0")
        #expect(listing.availableVersion(for: .avdmanager, installed: "19.0") == "20.0")
    }

    @Test func noUpdateWhenTheTableIsAbsent() {
        let listing = SDKRepositoryListingParser.parse(Fixture.text("sdkmanager-list-22"))
        #expect(listing.updates.isEmpty)
        #expect(listing.availableVersion(for: .emulator, installed: "37.2.13") == nil)
    }

    @Test func offersNewerCommandLineToolsWhenTheInstalledOneIsOlder() {
        let listing = SDKRepositoryListing(updates: [:], latestCommandLineTools: "20.0")
        #expect(listing.availableVersion(for: .sdkmanager, installed: "19.0") == "20.0")
        #expect(listing.availableVersion(for: .sdkmanager, installed: "20.0") == nil)
        #expect(listing.availableVersion(for: .sdkmanager, installed: nil) == nil)
    }

    @Test func readsTheUpdateArrowOfAndroidCLI23() {
        let listing = SDKRepositoryListingParser.parse(Fixture.text("sdkmanager-list-23"))
        #expect(listing.updates["cmdline-tools;latest"] == "23.0.0")
    }

    @Test func survivesEmptyAndGarbledOutput() {
        #expect(SDKRepositoryListingParser.parse("").updates.isEmpty)
        let garbage = "Installed packages:\n  | | |\n  ->\nAvailable Updates:\n  x |\n\u{0}\u{1}"
        #expect(SDKRepositoryListingParser.parse(garbage).updates.isEmpty)
    }

    @Test func splitsBothColumnLayouts() {
        let pipes = SDKRepositoryListingParser.columns(in: "  emulator   | 37.2.13 | Android Emulator | emulator")
        #expect(pipes == ["emulator", "37.2.13", "Android Emulator", "emulator"])
        let spaces = SDKRepositoryListingParser.columns(in: "  platforms/android-37.0     2.0.0     Android SDK Platform 37.0")
        #expect(spaces == ["platforms;android-37.0", "2.0.0", "Android SDK Platform 37.0"])
        #expect(SDKRepositoryListingParser.columns(in: "   ").isEmpty)
    }
}

struct StudioPackageCatalogueTests {
    @Test(arguments: ["sdkmanager-list-22", "sdkmanager-list-23"])
    func offersStablePlatformsFromAPI36NewestFirst(fixture: String) {
        let versions = StudioPackageCatalogue.offeredPlatforms(in: Fixture.text(fixture)).map(\.version)
        // No extensions (36-ext18) and no betas (37.2-beta1).
        #expect(versions.first == "37.2" || versions.first == "37.1" || versions.first == "37.0")
        #expect(versions.allSatisfy { AndroidAPIFloor.includes($0) })
        #expect(versions.contains("36"))
        #expect(versions.contains("37.0"))
        #expect(!versions.contains { $0.contains("ext") || $0.contains("beta") })
        #expect(versions == versions.sorted { VersionOrdering.isOlder($1, than: $0) })
    }

    @Test(arguments: ["sdkmanager-list-22", "sdkmanager-list-23"])
    func offersStableBuildToolsNewestFirst(fixture: String) {
        let versions = StudioPackageCatalogue.offeredBuildTools(in: Fixture.text(fixture)).map(\.version)
        #expect(versions.contains("36.0.0"))
        #expect(versions.contains("37.0.0"))
        #expect(!versions.contains { $0.contains("rc") })
        #expect(versions == versions.sorted { VersionOrdering.isOlder($1, than: $0) })
    }

    @Test func buildsInstallIdentifiersAndFolders() {
        let platform = StudioPackageCatalogue.offeredPlatforms(in: Fixture.text("sdkmanager-list-22"))
            .first { $0.version == "37.0" }
        #expect(platform?.installIdentifier == "platforms;android-37.0")
        #expect(platform?.relativeDirectory == "platforms/android-37.0")
        let tools = StudioPackageCatalogue.offeredBuildTools(in: Fixture.text("sdkmanager-list-22"))
            .first { $0.version == "37.0.0" }
        #expect(tools?.installIdentifier == "build-tools;37.0.0")
        #expect(tools?.relativeDirectory == "build-tools/37.0.0")
    }

    @Test func ignoresEmptyOutput() {
        #expect(StudioPackageCatalogue.offeredPlatforms(in: "").isEmpty)
        #expect(StudioPackageCatalogue.offeredBuildTools(in: "Loading package information...").isEmpty)
    }
}

struct PhoneSystemImageCatalogueTests {
    @Test(arguments: ["sdkmanager-list-22", "sdkmanager-list-23"])
    func offersOnlyGooglePlayArm64PhoneImages(fixture: String) {
        let images = PhoneSystemImageCatalogue.offered(in: Fixture.text(fixture))
        #expect(!images.isEmpty)
        for image in images {
            #expect(image.installIdentifier.hasSuffix(";google_apis_playstore;arm64-v8a"))
            #expect(AndroidAPIFloor.includes(image.api))
        }
        #expect(images.map(\.api) == images.map(\.api).sorted { VersionOrdering.isOlder($1, than: $0) })
    }

    @Test func skipsPageSizeTabletWearAndX86Images() {
        let images = PhoneSystemImageCatalogue.offered(in: Fixture.text("sdkmanager-list-22"))
        // Android 37.1 and 37.2 only ship 16 KB page images, so the newest phone image is 37.0.
        #expect(images.map(\.api) == ["37.0", "36.1", "36"])
    }

    @Test func buildsIdentifiersAndFolders() throws {
        let image = try #require(PhoneSystemImageCatalogue.offered(in: Fixture.text("sdkmanager-list-22")).first)
        #expect(image.installIdentifier == "system-images;android-37.0;google_apis_playstore;arm64-v8a")
        #expect(image.relativeDirectory == "system-images/android-37.0/google_apis_playstore/arm64-v8a")
        #expect(image.detail == "API 37.0 · Google Play · arm64-v8a")
    }
}

struct HardwareProfileCatalogueTests {
    private let profiles = HardwareProfileCatalogue.phones(in: Fixture.text("avdmanager-list-device"))

    @Test func keepsOnlyPixelPhones() {
        #expect(!profiles.isEmpty)
        for profile in profiles {
            #expect(profile.id == "pixel" || profile.id.hasPrefix("pixel_"))
            #expect(!profile.id.contains("fold"))
            #expect(!profile.id.contains("tablet"))
            #expect(profile.id != "pixel_c")
        }
    }

    @Test func listsTheNewestGenerationFirst() {
        #expect(profiles.first?.id == "pixel_10")
        #expect(profiles.first?.name == "Pixel 10")
        let ids = profiles.map(\.id)
        #expect(ids.firstIndex(of: "pixel_10")! < ids.firstIndex(of: "pixel_9")!)
        #expect(ids.firstIndex(of: "pixel_9a")! < ids.firstIndex(of: "pixel_8")!)
        #expect(ids.last == "pixel_xl" || ids.last == "pixel")
    }

    @Test func includesTheProfilesItKeeps() {
        let ids = Set(profiles.map(\.id))
        #expect(ids.contains("pixel_9a"))
        #expect(ids.contains("pixel_8a"))
    }

    @Test func ignoresEmptyOutput() {
        #expect(HardwareProfileCatalogue.phones(in: "").isEmpty)
    }
}

struct AVDListingTests {
    @Test func readsALoadedDevice() throws {
        let entries = AVDListing.entries(in: Fixture.text("avdmanager-list-avd"))
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.name == "Pixel_9a_API_37")
        #expect(entry.device == "pixel_9a (Google)")
        #expect(entry.path == "/Users/test/.android/avd/Pixel_9a_API_37.avd")
        #expect(entry.error == nil)
    }

    @Test func readsBothSectionsIncludingADeviceWhoseImageIsGone() {
        let entries = AVDListing.entries(in: Fixture.text("avdmanager-list-avd-missing-image"))
        #expect(entries.map(\.name) == ["Pixel_9a_API_37", "Pixel_8a"])
        #expect(entries[0].error == nil)
        #expect(entries[1].error?.contains("Missing system image") == true)
    }

    @Test func listsNothingForEmptyOutput() {
        #expect(AVDListing.entries(in: "").isEmpty)
        #expect(AVDListing.entries(in: "Available Android Virtual Devices:\n").isEmpty)
    }
}

struct ADBDeviceListTests {
    @Test func keepsOnlyReadyEmulators() {
        let serials = ADBDeviceList.emulatorSerials(in: Fixture.text("adb-devices"))
        // Not the offline or unauthorized emulators, and not the physical phone.
        #expect(serials == ["emulator-5554", "emulator-5560"])
    }

    @Test func readsTheDeviceNameAndSkipsTheStatusLine() {
        #expect(ADBDeviceList.avdName(in: Fixture.text("adb-emu-avd-name")) == "Pixel_9a_API_37")
    }

    @Test func handlesEmptyOutput() {
        #expect(ADBDeviceList.emulatorSerials(in: "").isEmpty)
        #expect(ADBDeviceList.emulatorSerials(in: "List of devices attached\n\n").isEmpty)
        #expect(ADBDeviceList.avdName(in: "OK\n") == nil)
        #expect(ADBDeviceList.avdName(in: "") == nil)
    }
}

struct SDKLicensePromptParserTests {
    @Test func findsTheLicenseAndItsText() throws {
        let output = Fixture.text("sdkmanager-license-prompt")
        let pending = try #require(SDKLicensePromptParser.next(in: output, handledCharacters: 0))
        #expect(pending.prompt.name == "android-sdk-license")
        #expect(pending.prompt.text.hasPrefix("Terms and Conditions"))
        #expect(pending.prompt.text.contains("Software Development Kit License Agreement"))
        #expect(!pending.prompt.text.contains("Accept?"))
    }

    @Test func doesNotAnswerTheSamePromptTwice() throws {
        let output = Fixture.text("sdkmanager-license-prompt")
        let first = try #require(SDKLicensePromptParser.next(in: output, handledCharacters: 0))
        #expect(SDKLicensePromptParser.next(in: output, handledCharacters: first.handledCharacters) == nil)
    }

    @Test func waitsWhileThePromptIsIncomplete() {
        let partial = "License android-sdk-license:\n---------------------------------------\nTerms and Con"
        #expect(SDKLicensePromptParser.next(in: partial, handledCharacters: 0) == nil)
    }

    @Test func rejectsOffsetsOutsideTheOutput() {
        #expect(SDKLicensePromptParser.next(in: "abc", handledCharacters: 99) == nil)
        #expect(SDKLicensePromptParser.next(in: "abc", handledCharacters: -1) == nil)
    }

    @Test func fallsBackToTheWholeBlockWithoutDelimiters() {
        let prompt = SDKLicensePromptParser.parse("Some unexpected text")
        #expect(prompt.name == "Android SDK license")
        #expect(prompt.text == "Some unexpected text")
    }
}

struct SDKInstallReportTests {
    @Test func reportsTheLineThatSaysWhatFailed() {
        let message = SDKInstallReport.failureMessage(in: Fixture.text("sdkmanager-install-failure"))
        #expect(message == "Install failed: platforms;android-99 (platforms;android-99)")
    }

    @Test func ignoresWarningsAndTheLicensePrompt() {
        let output = "Warning: Something odd\nAccept? (y/N):\n"
        #expect(SDKInstallReport.failureMessage(in: output) == "The package could not be updated.")
    }

    @Test func fallsBackToTheLastLine() {
        #expect(SDKInstallReport.failureMessage(in: "first\nsecond\n") == "second")
    }

    @Test func clipsVeryLongLines() {
        let message = SDKInstallReport.failureMessage(in: "error: " + String(repeating: "x", count: 500))
        #expect(message.count == 240)
        #expect(message.hasSuffix("…"))
    }
}

struct VersionOrderingTests {
    @Test func comparesNumbersNotText() {
        #expect(VersionOrdering.isOlder("9.0.0", than: "10.0.0"))
        #expect(VersionOrdering.isOlder("1.9", than: "1.10"))
        #expect(!VersionOrdering.isOlder("10.0.0", than: "9.0.0"))
    }

    @Test func treatsMissingComponentsAsZero() {
        #expect(!VersionOrdering.isOlder("37.0", than: "37.0.0"))
        #expect(!VersionOrdering.isOlder("37.0.0", than: "37.0"))
        #expect(VersionOrdering.isOlder("36", than: "36.1"))
    }

    @Test func equalVersionsAreNotOlder() {
        #expect(!VersionOrdering.isOlder("37.2.13", than: "37.2.13"))
    }

    @Test func ignoresAPreReleaseSuffix() {
        #expect(!VersionOrdering.isOlder("36.0.0-rc1", than: "36.0.0"))
    }

    @Test func androidAPIFloorKeepsAPI36AndAbove() {
        #expect(AndroidAPIFloor.includes("36"))
        #expect(AndroidAPIFloor.includes("37.2"))
        #expect(!AndroidAPIFloor.includes("35"))
        #expect(!AndroidAPIFloor.includes("abc"))
        #expect(!AndroidAPIFloor.includes(""))
    }
}

struct AVDNameTests {
    @Test func turnsSpacesIntoUnderscores() {
        #expect(AVDName.normalized("  Pixel 9a  ") == "Pixel_9a")
    }

    @Test(arguments: ["Pixel_9a", "a.b-c_1", "X"])
    func acceptsNamesAvdmanagerAllows(name: String) {
        #expect(AVDName.isValid(name))
    }

    @Test(arguments: ["", "Pixel 9a", "Pixel/9a", "é", "a;b", "../x"])
    func rejectsOthers(name: String) {
        #expect(!AVDName.isValid(name))
    }

    @Test func suggestsANameFromTheProfileAndImage() {
        let profile = HardwareProfile(id: "pixel_9a", name: "Pixel 9a")
        let image = PhoneSystemImage(api: "37.0", installIdentifier: "", relativeDirectory: "")
        #expect(AVDName.suggestion(profile: profile, image: image, taken: []) == "Pixel_9a_API_37")
    }

    @Test func addsANumberWhenTheNameIsTaken() {
        let profile = HardwareProfile(id: "pixel_9a", name: "Pixel 9a")
        let image = PhoneSystemImage(api: "37.0", installIdentifier: "", relativeDirectory: "")
        let taken: Set<String> = ["Pixel_9a_API_37", "Pixel_9a_API_37_2"]
        #expect(AVDName.suggestion(profile: profile, image: image, taken: taken) == "Pixel_9a_API_37_3")
    }
}
