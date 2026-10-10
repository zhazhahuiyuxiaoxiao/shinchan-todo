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
    public static func applicationStore() -> FileFocusStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileFocusStore(url: root.appendingPathComponent("local.zhazhahui.shinchan-todo/Focus.json"))
    }
    public func load() throws -> FocusArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return FocusArchive() }
        do { return try JSONDecoder().decode(FocusArchive.self, from: Data(contentsOf: url)).validated() }
        catch { throw FocusError.invalidFile }
    }
    public func save(_ archive: FocusArchive) throws {
        let checked = try archive.validated()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(checked)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
