import Foundation

/// Reads a text fixture from the test bundle.
enum Fixture {
    private final class BundleToken {}

    static func text(_ name: String, _ ext: String = "txt") -> String {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Missing fixture \(name).\(ext)")
        }
        return text
    }
}

/// A scratch folder that disappears with the test.
final class ScratchFolder {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appending(path: "DroidDeskTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func folder(_ path: String) -> URL {
        let folder = url.appending(path: path, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @discardableResult
    func file(_ path: String, _ text: String = "", executable: Bool = false) -> URL {
        let file = url.appending(path: path)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: file, atomically: true, encoding: .utf8)
        if executable {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return file
    }
}
