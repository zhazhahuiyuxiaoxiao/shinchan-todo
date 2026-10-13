import Foundation
import TodoCore

@MainActor public final class MemoryFocusStore: FocusStore {
    private var archive = FocusArchive()
    public init() {}
    public func load() throws -> FocusArchive { archive }
    public func save(_ archive: FocusArchive) throws { self.archive = try archive.validated() }
}
@MainActor public final class FileFocusStore: FocusStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public var legacyBackupURL: URL { url.appendingPathExtension("v1.backup") }
    public static func applicationStore() -> FileFocusStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileFocusStore(url: root.appendingPathComponent("local.zhazhahui.shinchan-todo/Focus.json"))
    }
    public func load() throws -> FocusArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return FocusArchive() }
        do { return try JSONDecoder().decode(FocusArchive.self, from: Data(contentsOf: url)).upgraded() }
        catch { throw FocusError.invalidFile }
    }
    public func save(_ archive: FocusArchive) throws {
        let checked = try archive.validated()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Back up the exact v1 bytes before the first v2 write. Never overwrite damaged input or a conflicting backup.
        if FileManager.default.fileExists(atPath: url.path) {
            let original = try Data(contentsOf: url)
            let existing = try JSONDecoder().decode(FocusArchive.self, from: original).validated()
            if existing.version == 1 && checked.version == 2 {
                if FileManager.default.fileExists(atPath: legacyBackupURL.path) {
                    guard try Data(contentsOf: legacyBackupURL) == original else { throw FocusError.invalidFile }
                } else {
                    try original.write(to: legacyBackupURL, options: .atomic)
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyBackupURL.path)
            }
        }
        let data = try JSONEncoder().encode(checked)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
