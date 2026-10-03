import Foundation
import Combine
import FamilyControls
import ManagedSettings
import DeviceActivity
import DopagakiCore

@MainActor
final class ScreenTimeService: ObservableObject {
    @Published private(set) var isAuthorized = false
    @Published private(set) var isEnabled = false
    @Published var selection = FamilyActivitySelection()
    @Published var lastError: String?
    @Published private(set) var resetHour = 6
    @Published private(set) var temporaryUnlockUntil: Date?
    @Published private(set) var unlockHistory: [Date] = []
    private var policy: ScreenTimePolicy
    private let repository: StateRepository
    private let center = DeviceActivityCenter()
    private var registeredTimeZoneID: String?

    init(repository: StateRepository) {
        self.repository = repository
        policy = (try? ScreenTimePolicy.load()) ?? ScreenTimePolicy()
        selection = policy.selection
        isEnabled = policy.enabled
        resetHour = policy.resetHour
        temporaryUnlockUntil = policy.temporaryUnlockUntil
        unlockHistory = policy.unlockHistory
        refreshAuthorization()
    }

    func refreshAuthorization() {
        #if DOPA_PERSONAL_TEAM
        isAuthorized = false
        #else
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        if !isAuthorized { ManagedSettingsStore(named: ScreenTimePolicy.storeName).clearAllSettings() }
        #endif
    }

    func requestAuthorization() async {
        #if DOPA_PERSONAL_TEAM
        lastError = "この実機確認版にはScreen Timeのアプリ制限を含みません。"
        #elseif targetEnvironment(simulator)
        lastError = "Screen Timeの許可・制限は、署名を設定した実機で確認してください。"
        #else
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshAuthorization()
            lastError = nil
        } catch { lastError = "Screen Timeを許可できませんでした：\(error.localizedDescription)" }
        #endif
    }

    func setEnabled(_ value: Bool) {
        guard value else {
            var draft = policy
            draft.enabled = false
            guard commitPolicy(draft) else { return }
            center.stopMonitoring([ScreenTimePolicy.dailyActivity, ScreenTimePolicy.escapeActivity])
            ManagedSettingsStore(named: ScreenTimePolicy.storeName).clearAllSettings()
            return
        }
        refreshAuthorization()
        guard isAuthorized else { lastError = "まずScreen Timeの利用を許可してください。"; return }
        guard policy.hasSelection else { lastError = "制限するアプリを選択してください。"; return }
        guard AppConfiguration.sharedDirectory != nil else { lastError = ScreenTimePolicy.PolicyError.groupUnavailable.localizedDescription; return }
        do {
            try scheduleDaily(hour: policy.resetHour)
            var draft = policy
            draft.enabled = true
            guard commitPolicy(draft) else {
                center.stopMonitoring([ScreenTimePolicy.dailyActivity])
                return
            }
            restoreRestrictions()
        } catch {
            center.stopMonitoring([ScreenTimePolicy.dailyActivity])
            lastError = "自動制限を設定できませんでした：\(error.localizedDescription)"
        }
    }

    func updateSelection(_ value: FamilyActivitySelection) {
        var draft = policy
        draft.selection = value
        guard commitPolicy(draft) else { return }
        restoreRestrictions()
    }

    func setResetHour(_ hour: Int) {
        var draft = policy
        draft.resetHour = min(23, max(0, hour))
        if (draft.earnedUnlockUntil ?? .distantPast) > Date() {
            draft.earnedUnlockUntil = draft.nextReset(after: Date(), calendar: Calendar.current)
        }
        if isEnabled {
            do { try scheduleDaily(hour: draft.resetHour) }
            catch { lastError = "翌日の制限時刻を設定できませんでした：\(error.localizedDescription)"; return }
        }
        if !commitPolicy(draft), isEnabled {
            try? scheduleDaily(hour: policy.resetHour)
        }
    }

    func sync(with state: AppState) {
        refreshAuthorization()
        guard isAuthorized else { return }
        let now = Date()
        if isEnabled && registeredTimeZoneID != TimeZone.current.identifier {
            do {
                try scheduleDaily(hour: policy.resetHour)
                var draft = policy
                if (draft.earnedUnlockUntil ?? .distantPast) > now {
                    draft.earnedUnlockUntil = draft.nextReset(after: now, calendar: Calendar.current)
                }
                _ = commitPolicy(draft)
            } catch { lastError = "翌日の制限スケジュールを更新できませんでした：\(error.localizedDescription)" }
        }
        let must = state.occurrences(on: now).filter(\.isMust)
        if isEnabled && !must.isEmpty && must.allSatisfy(\.isCompleted), (policy.earnedUnlockUntil ?? .distantPast) <= now {
            // Once earned, adding another must does not unexpectedly relock this cycle.
            var draft = policy
            draft.earnedUnlockUntil = draft.nextReset(after: now, calendar: Calendar.current)
            _ = commitPolicy(draft)
        }
        policy.apply(to: state, at: now)
        temporaryUnlockUntil = (policy.temporaryUnlockUntil ?? .distantPast) > now ? policy.temporaryUnlockUntil : nil
    }

    func temporarilyUnlock(minutes: Int) {
        guard isEnabled, isAuthorized else { return }
        let now = Date()
        // DeviceActivity's date components have second precision. Keep the saved expiry identical.
        let end = Date(timeIntervalSince1970: ceil(now.timeIntervalSince1970) + Double(max(15, minutes)) * 60)
        do {
            try scheduleEscape(from: now, until: end)
            var draft = policy
            draft.temporaryUnlockUntil = end
            draft.unlockHistory.append(now)
            guard commitPolicy(draft) else {
                let saveError = lastError
                do {
                    if let oldEnd = policy.temporaryUnlockUntil, oldEnd > now {
                        // Restore the full old interval, even if fewer than 15 minutes remain.
                        let oldStart = policy.unlockHistory.last ?? oldEnd.addingTimeInterval(-900)
                        try scheduleEscape(from: oldStart, until: oldEnd)
                    } else {
                        center.stopMonitoring([ScreenTimePolicy.escapeActivity])
                    }
                    restoreRestrictions()
                    lastError = saveError
                } catch {
                    center.stopMonitoring([ScreenTimePolicy.escapeActivity])
                    var enforced = policy
                    enforced.temporaryUnlockUntil = nil
                    if let state = try? repository.load() { enforced.apply(to: state) }
                    temporaryUnlockUntil = nil
                    lastError = "一時解除の変更を保存・復元できないため制限を再適用しました。\(error.localizedDescription)"
                }
                return
            }
            ManagedSettingsStore(named: ScreenTimePolicy.storeName).clearAllSettings()
            lastError = nil
        } catch { lastError = "一時解除を設定できませんでした：\(error.localizedDescription)" }
    }

    func restoreRestrictions() {
        do { sync(with: try repository.load()) }
        catch { lastError = "タスクの状態を読み込めないため制限を更新できません：\(error.localizedDescription)" }
    }

    private func scheduleDaily(hour: Int) throws {
        let calendar = Calendar.current
        var start = DateComponents(hour: hour, minute: 0)
        start.calendar = calendar
        start.timeZone = calendar.timeZone
        var end = DateComponents(hour: (hour + 23) % 24, minute: 59)
        end.calendar = calendar
        end.timeZone = calendar.timeZone
        let schedule = DeviceActivitySchedule(
            intervalStart: start, intervalEnd: end, repeats: true)
        try center.startMonitoring(ScreenTimePolicy.dailyActivity, during: schedule)
        registeredTimeZoneID = calendar.timeZone.identifier
    }

    private func scheduleEscape(from start: Date, until end: Date) throws {
        let calendar = Calendar.current
        var from = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        var until = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end)
        from.calendar = calendar
        from.timeZone = calendar.timeZone
        until.calendar = calendar
        until.timeZone = calendar.timeZone
        try center.startMonitoring(ScreenTimePolicy.escapeActivity, during: DeviceActivitySchedule(intervalStart: from, intervalEnd: until, repeats: false))
    }

    @discardableResult private func commitPolicy(_ draft: ScreenTimePolicy) -> Bool {
        do {
            try draft.save()
            policy = draft
            selection = draft.selection
            isEnabled = draft.enabled
            resetHour = draft.resetHour
            temporaryUnlockUntil = (draft.temporaryUnlockUntil ?? .distantPast) > Date() ? draft.temporaryUnlockUntil : nil
            unlockHistory = draft.unlockHistory
            lastError = nil
            return true
        } catch { lastError = "制限の設定を保存できませんでした：\(error.localizedDescription)"; return false }
    }
}
