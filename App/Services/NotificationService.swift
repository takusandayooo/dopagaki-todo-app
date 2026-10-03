import Foundation
import UserNotifications
import DopagakiCore

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var revision = 0
    private var latestState: AppState?
    private var worker: Task<Void, Never>?
    var onOpenOccurrence: ((UUID) -> Void)?
    var onOpenTask: ((UUID) -> Void)?
    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func reconcile(state: AppState) async {
        guard !Task.isCancelled else { return }
        latestState = state
        revision += 1
        if let worker { await worker.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while let snapshot = self.latestState {
                self.latestState = nil
                await self.apply(state: snapshot, currentRevision: self.revision)
            }
            self.worker = nil
        }
        worker = task
        await task.value
    }

    /// A single worker serializes remove/add operations. New snapshots replace the pending work.
    private func apply(state: AppState, currentRevision: Int) async {
        let pending = await center.pendingNotificationRequests()
        guard revision == currentRevision else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("dopa.") })
        let settings = await center.notificationSettings()
        guard revision == currentRevision, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let now = Date()
        if state.settings.remindersEnabled {
            let dailyLimit = min(5, max(0, state.settings.reminderDailyLimit))
            var requests: [UNNotificationRequest] = []
            let calendar = state.calendar
            var snapshot = state
            // Rebuild a bounded seven-day queue; no repeating notification can linger after completion.
            for dayOffset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                snapshot.ensureOccurrences(on: day)
                let progress = WidgetDayProgress(state: snapshot, on: day)
                let pendingTasks = snapshot.occurrences(on: day).filter { !$0.isCompleted }
                var dayRequests: [UNNotificationRequest] = []
                for occurrence in pendingTasks {
                    guard let task = state.tasks.first(where: { $0.id == occurrence.taskID }), let reminder = task.reminder else { continue }
                    let triggerDate: Date
                    if task.recurrence.frequency == .none { triggerDate = reminder }
                    else {
                        let time = calendar.dateComponents([.hour, .minute], from: reminder)
                        triggerDate = calendar.date(bySettingHour: time.hour ?? 19, minute: time.minute ?? 0, second: 0, of: day) ?? day
                    }
                    if triggerDate > now, calendar.isDate(triggerDate, inSameDayAs: day) {
                        dayRequests.append(request(id: "dopa.task.\(task.id).\(snapshot.dayKey(for: day))", title: occurrence.title, body: "取り組む時間です。\(progress.reminderText)", date: triggerDate, taskID: task.id, sound: state.settings.soundEnabled, calendar: calendar))
                    }
                }
                if let next = pendingTasks.first {
                    for offset in 0..<dailyLimit {
                        let hour = min(23, max(0, state.settings.reminderHour) + offset)
                        guard let date = calendar.date(bySettingHour: hour, minute: (offset * 17) % 60, second: 0, of: day), date > now else { continue }
                        dayRequests.append(request(id: "dopa.nudge.\(snapshot.dayKey(for: day)).\(offset)", title: "ドパギキ", body: progress.reminderText, date: date, taskID: next.taskID, sound: state.settings.soundEnabled, calendar: calendar))
                    }
                }
                requests.append(contentsOf: dayRequests.prefix(dailyLimit))
            }
            for item in requests.prefix(35) {
                guard revision == currentRevision else { return }
                try? await center.add(item)
            }
        }
        guard revision == currentRevision else { return }
        if let focus = state.activeFocus, focus.mode == .countdown, !focus.isPaused, let target = focus.targetSeconds {
            let remaining = target - focus.elapsed(at: now)
            if remaining > 0 {
                let content = UNMutableNotificationContent()
                content.title = "目標時間になった！"
                content.body = "おつかれさま。記録を保存するか、もう少し続けよう。"
                content.userInfo = ["occurrenceID": focus.occurrenceID.uuidString]
                if state.settings.soundEnabled { content.sound = .default }
                let item = UNNotificationRequest(identifier: "dopa.timer", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false))
                try? await center.add(item)
            }
        }
    }

    private func request(id: String, title: String, body: String, date: Date, taskID: UUID, sound: Bool, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["taskID": taskID.uuidString]
        if sound { content.sound = .default }
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        parts.timeZone = calendar.timeZone
        return UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let value = response.notification.request.content.userInfo["taskID"] as? String, let id = UUID(uuidString: value) {
            Task { @MainActor [weak self] in self?.onOpenTask?(id) }
        }
        if let value = response.notification.request.content.userInfo["occurrenceID"] as? String, let id = UUID(uuidString: value) {
            Task { @MainActor [weak self] in self?.onOpenOccurrence?(id) }
        }
        completionHandler()
    }
}
