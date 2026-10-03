import Foundation
import DopagakiCore

/// The Watch app writes; its WidgetKit extension only reads this atomic snapshot.
struct WatchProgressRepository {
    private static let lock = NSLock()
    let directory: URL?
    init(directory: URL? = Self.sharedDirectory) { self.directory = directory }

    static var sharedDirectory: URL? {
        #if os(watchOS)
        let group = Bundle.main.object(forInfoDictionaryKey: "DopaAppGroup") as? String ?? "group.dev.dopagaki.todo"
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        #else
        return nil
        #endif
    }

    func load() throws -> WatchProgressTransfer? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent("watch-progress-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try WatchProgressTransfer.decode(Data(contentsOf: url))
    }

    @discardableResult func receive(_ data: Data) throws -> Bool {
        let incoming = try WatchProgressTransfer.decode(data)
        guard let directory else { throw RepositoryError.groupUnavailable }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        // A late immediate-message reply must not replace a newer background delivery.
        if let current = try? load(), incoming.updatedAt <= current.updatedAt { return false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("watch-progress-v1.json")
        try JSONEncoder().encode(incoming).write(to: url, options: .atomic)
        return true
    }

    enum RepositoryError: Error { case groupUnavailable }
}
