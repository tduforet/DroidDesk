import Foundation

/// One Android virtual device from `avdmanager list avd`, filled in from its `config.ini`.
struct VirtualDevice: Identifiable, Equatable, Sendable {
    var name: String
    var title: String
    var detail: String
    var readiness: Readiness

    var id: String { name }

    enum Readiness: Equatable, Sendable {
        case stopped
        case missingImage

        var label: String {
            switch self {
            case .stopped: "Stopped"
            case .missingImage: "Missing image"
            }
        }
    }
}

enum AVDListing {
    struct Entry: Equatable, Sendable {
        var name: String
        var path: String?
        var device: String?
        var error: String?
    }

    /// Both sections of `avdmanager list avd`: devices that load, and devices whose image is gone.
    static func entries(in output: String) -> [Entry] {
        var entries: [Entry] = []
        var fields: [String: String] = [:]

        func finish() {
            guard let name = fields["Name"], !name.isEmpty else {
                fields = [:]
                return
            }
            entries.append(Entry(name: name, path: fields["Path"], device: fields["Device"], error: fields["Error"]))
            fields = [:]
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "---------" {
                finish()
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard key == "Name" || key == "Path" || key == "Device" || key == "Error" else { continue }
            if key == "Name", fields["Name"] != nil { finish() }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        finish()
        return entries
    }
}

enum AVDConfig {
    static func read(directory: URL) -> [String: String] {
        values(in: directory.appending(path: "config.ini"))
    }

    static func values(in file: URL) -> [String: String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            values[key] = value
        }
        return values
    }
}

enum VirtualDeviceReader {
    static func device(from entry: AVDListing.Entry, sdkRoot: URL) -> VirtualDevice {
        let config = entry.path.map { AVDConfig.read(directory: URL(fileURLWithPath: $0, isDirectory: true)) } ?? [:]
        let image = imageReference(config: config, error: entry.error)
        let profile = useful(config["hw.device.name"]) ?? entry.device.flatMap(profileName)
        let detail = [
            profile,
            image.api.map { "API \($0)" },
            image.tag.map(tagLabel),
            image.abi,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        return VirtualDevice(
            name: entry.name,
            title: useful(config["avd.ini.displayname"]) ?? entry.name,
            detail: detail,
            readiness: readiness(directory: image.directory, error: entry.error, sdkRoot: sdkRoot)
        )
    }

    private struct ImageReference {
        var directory: String?
        var api: String?
        var tag: String?
        var abi: String?
    }

    private static func imageReference(config: [String: String], error: String?) -> ImageReference {
        let sysdir = useful(config["image.sysdir.1"])
        let parts = sysdir?.split(separator: "/").map(String.init) ?? []
        let fromPath = parts.count >= 4 && parts[0] == "system-images"
        let fallback = error.flatMap(missingImagePath)
        return ImageReference(
            directory: sysdir ?? fallback.map { "system-images/\($0)" },
            api: apiLevel(in: fromPath ? parts[1] : (useful(config["target"]) ?? fallback ?? sysdir ?? "")),
            tag: useful(config["tag.id"]) ?? (fromPath ? parts[2] : nil) ?? fallback.flatMap(pathTag),
            abi: useful(config["abi.type"]) ?? (fromPath ? parts[3] : nil) ?? fallback.flatMap(pathABI)
        )
    }

    /// `android-36/google_apis_playstore/arm64-v8a` from avdmanager's missing-image error.
    private static func missingImagePath(_ error: String) -> String? {
        guard let start = error.range(of: "android-") else { return nil }
        let token = error[start.lowerBound...].prefix { $0 != " " && $0 != "." }
        let path = String(token)
        guard path.split(separator: "/").count == 3 else { return nil }
        return path
    }

    private static func pathTag(_ path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        return parts.count >= 2 ? parts[1] : nil
    }

    private static func pathABI(_ path: String) -> String? {
        path.split(separator: "/").map(String.init).last
    }

    private static func readiness(directory: String?, error: String?, sdkRoot: URL) -> VirtualDevice.Readiness {
        guard let directory else { return error == nil ? .stopped : .missingImage }
        return imageIsInstalled(directory, sdkRoot: sdkRoot) ? .stopped : .missingImage
    }

    private static func imageIsInstalled(_ relativeDirectory: String, sdkRoot: URL) -> Bool {
        let relative = relativeDirectory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        let url = sdkRoot.appending(path: relative, directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func apiLevel(in text: String) -> String? {
        guard let match = text.firstMatch(of: /android-(\d+(?:\.\d+)?)/) else { return nil }
        return String(match.1)
    }

    private static func tagLabel(_ id: String) -> String {
        switch id {
        case "google_apis_playstore": "Google Play"
        case "google_apis": "Google APIs"
        case "default": "Default"
        case "google_atd", "aosp_atd": "Automated Test"
        default: id.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// `pixel_8a (Google)` keeps the profile id.
    private static func profileName(_ device: String) -> String? {
        let name = device.split(separator: "(", maxSplits: 1).first.map(String.init) ?? device
        return useful(name.trimmingCharacters(in: .whitespaces))
    }

    private static func useful(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "<build>" else { return nil }
        return trimmed
    }
}

/// A phone system image Virtual Devices can install: Google Play, arm64, API 36 or newer.
struct PhoneSystemImage: Identifiable, Equatable, Sendable {
    var api: String
    var installIdentifier: String
    var relativeDirectory: String

    var id: String { installIdentifier }
    var title: String { "System image" }
    var detail: String { "API \(api) · Google Play · arm64-v8a" }
}

struct PhoneSystemImageStatus: Identifiable, Equatable, Sendable {
    var image: PhoneSystemImage
    var isInstalled: Bool

    var id: String { image.id }
}

enum PhoneSystemImageCatalogue {
    /// Stable Google Play arm64 phone images from API 36 upward, newest first.
    /// Extensions, betas, 16 KB page images, and other form factors are left out.
    static func offered(in listOutput: String) -> [PhoneSystemImage] {
        var byIdentifier: [String: PhoneSystemImage] = [:]
        for rawLine in listOutput.split(whereSeparator: \.isNewline) {
            guard let identifier = SDKRepositoryListingParser.columns(in: String(rawLine)).first,
                  let image = image(identifier: identifier) else { continue }
            byIdentifier[image.id] = image
        }
        return sorted(Array(byIdentifier.values))
    }

    static func installed(in sdkRoot: URL) -> [PhoneSystemImage] {
        let root = sdkRoot.appending(path: "system-images", directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [] }
        let images = entries.compactMap { entry -> PhoneSystemImage? in
            guard let image = image(apiDirectory: entry.lastPathComponent), isInstalled(image, in: sdkRoot) else {
                return nil
            }
            return image
        }
        return sorted(images)
    }

    static func isInstalled(_ image: PhoneSystemImage, in sdkRoot: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let url = sdkRoot.appending(path: image.relativeDirectory, directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func image(identifier: String) -> PhoneSystemImage? {
        let pattern = /system-images;android-(\d+(?:\.\d+)?);google_apis_playstore;arm64-v8a/
        guard let api = identifier.wholeMatch(of: pattern)?.1 else { return nil }
        return make(api: String(api))
    }

    private static func image(apiDirectory: String) -> PhoneSystemImage? {
        let pattern = /android-(\d+(?:\.\d+)?)/
        guard let api = apiDirectory.wholeMatch(of: pattern)?.1 else { return nil }
        return make(api: String(api))
    }

    private static func make(api: String) -> PhoneSystemImage? {
        guard AndroidAPIFloor.includes(api) else { return nil }
        return PhoneSystemImage(
            api: api,
            installIdentifier: "system-images;android-\(api);google_apis_playstore;arm64-v8a",
            relativeDirectory: "system-images/android-\(api)/google_apis_playstore/arm64-v8a"
        )
    }

    private static func sorted(_ images: [PhoneSystemImage]) -> [PhoneSystemImage] {
        images.sorted { VersionOrdering.isOlder($1.api, than: $0.api) }
    }
}

enum AVDLocation {
    static var directory: URL {
        if let value = ProcessInfo.processInfo.environment["ANDROID_AVD_HOME"], !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".android/avd", directoryHint: .isDirectory)
    }
}
