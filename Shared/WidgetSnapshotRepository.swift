import Foundation
import DopagakiCore

struct WidgetSnapshotRepository {
    static let kind = "DopagakiMustProgress"
    private let directory: URL?

    init(directory: URL? = Self.sharedDirectory) { self.directory = directory }

    static var sharedDirectory: URL? {
        #if os(iOS)
        let group = Bundle.main.object(forInfoDictionaryKey: "DopaAppGroup") as? String ?? "group.dev.dopagaki.todo"
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        #else
        return nil
        #endif
    }

    func load() throws -> WidgetProgressSnapshot? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent("widget-progress-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(WidgetProgressSnapshot.self, from: Data(contentsOf: url))
    }

    /// Returns true only when the projection changes, avoiding reloads on every timer tick.
    @discardableResult func save(_ snapshot: WidgetProgressSnapshot) throws -> Bool {
        guard let directory else { return false }
        if let previous = try? load(), previous == snapshot { return false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("widget-progress-v1.json")
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
        return true
    }
}
