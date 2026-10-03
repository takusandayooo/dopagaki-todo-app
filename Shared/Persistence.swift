import Foundation
import DopagakiCore

enum AppConfiguration {
    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "DopaAppGroup") as? String ?? "group.dev.dopagaki.todo"
    }
    static var sharedDirectory: URL? {
        #if os(iOS) && !DOPA_PERSONAL_TEAM
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        #else
        return nil
        #endif
    }
}

/// Both the app and monitor read this snapshot. Only the app writes task data.
public final class StateRepository {
    public let directory: URL
    public var stateURL: URL { directory.appendingPathComponent("state-v1.json") }
    public var photosDirectory: URL { directory.appendingPathComponent("Photos", isDirectory: true) }

    public init(directory: URL? = nil) {
        self.directory = directory ?? AppConfiguration.sharedDirectory ??
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Dopagaki", isDirectory: true)
    }

    public func load() throws -> AppState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return AppState() }
        return try JSONDecoder().decode(AppState.self, from: Data(contentsOf: stateURL))
    }

    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: stateURL.path)
        #endif
    }

    /// Preserve unreadable data before allowing a new snapshot to be written.
    public func preserveUnreadableSnapshot() throws -> URL {
        let backup = directory.appendingPathComponent("state-backup-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: stateURL, to: backup)
        return backup
    }

    public func savePhoto(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try data.write(to: photosDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    public func photoURL(_ name: String) -> URL? {
        guard name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        let url = photosDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
