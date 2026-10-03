import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import DopagakiCore

struct ScreenTimePolicy: Codable {
    var enabled = false
    var selection = FamilyActivitySelection()
    var resetHour = 6
    var earnedUnlockUntil: Date?
    var temporaryUnlockUntil: Date?
    var unlockHistory: [Date] = []

    static let storeName = ManagedSettingsStore.Name("dopagaki.must")
    static let dailyActivity = DeviceActivityName("dopagaki.daily")
    static let escapeActivity = DeviceActivityName("dopagaki.escape")

    static var url: URL? { AppConfiguration.sharedDirectory?.appendingPathComponent("screen-time-v1.json") }

    static func load() throws -> Self {
        guard let url else { throw PolicyError.groupUnavailable }
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func save() throws {
        guard let url = Self.url else { throw PolicyError.groupUnavailable }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    func nextReset(after now: Date, calendar: Calendar) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: resetHour, minute: 0), matchingPolicy: .nextTimePreservingSmallerComponents) ?? now.addingTimeInterval(86_400)
    }

    func apply(to state: AppState, at now: Date = Date()) {
        let store = ManagedSettingsStore(named: Self.storeName)
        guard enabled, hasSelection else { store.clearAllSettings(); return }
        if (earnedUnlockUntil ?? .distantPast) > now || (temporaryUnlockUntil ?? .distantPast) > now {
            store.clearAllSettings(); return
        }
        var snapshot = state
        snapshot.ensureOccurrences(on: now)
        guard !snapshot.todaysMustComplete(on: now) else { store.clearAllSettings(); return }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    enum PolicyError: LocalizedError {
        case groupUnavailable
        var errorDescription: String? { "App Groupsの設定が必要です。Xcodeでアプリと拡張機能に同じグループを設定してください。" }
    }
}
