import Foundation
import Combine
import UIKit
import DopagakiCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var state: AppState
    @Published var lastError: String?
    @Published var completion: CompletionPresentation?
    @Published var notificationOccurrenceID: UUID?
    let screenTime: ScreenTimeService
    private let repository: StateRepository
    private let notifications = NotificationService()
    private var persistenceBlocked = false
    private var notificationTask: Task<Void, Never>?

    init() {
        let repository = StateRepository()
        self.repository = repository
        var initial = AppState()
        var loadMessage: String?
        var blocked = false
        do { initial = try repository.load() }
        catch {
            do {
                let backup = try repository.preserveUnreadableSnapshot()
                loadMessage = "保存データを読み込めませんでした。元データを\(backup.lastPathComponent)に保管しました。"
            } catch {
                blocked = true
                loadMessage = "保存データを読み込めません。元データを保護するため保存を停止しています。"
            }
        }
        initial.ensureOccurrences(on: Date())
        state = initial
        screenTime = ScreenTimeService(repository: repository)
        lastError = loadMessage
        persistenceBlocked = blocked
        notifications.onOpenOccurrence = { [weak self] id in self?.notificationOccurrenceID = id }
        notifications.onOpenTask = { [weak self] taskID in
            guard let self else { return }
            self.refreshToday()
            self.notificationOccurrenceID = self.today.first { $0.taskID == taskID }?.id
        }
        if !blocked { commit(initial) }
        if let loadMessage { lastError = loadMessage }
    }

    var today: [TaskOccurrence] { state.occurrences(on: Date()) }
    var currentTask: TaskOccurrence? {
        guard let focus = state.activeFocus else { return nil }
        return state.occurrences.first { $0.id == focus.occurrenceID }
    }
    var totalMust: Int { today.filter(\.isMust).count }
    var mustRemaining: Int { today.filter { $0.isMust && !$0.isCompleted }.count }
    var todaySeconds: Double { state.activity(on: Date()).seconds }

    func refreshToday() {
        var draft = state
        draft.ensureOccurrences(on: Date())
        commit(draft)
    }

    func addOrUpdateTask(_ task: TaskDefinition) {
        guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { lastError = "タスク名を入力してください。"; return }
        var draft = state
        draft.saveTask(task, on: Date())
        if task.reminder != nil { draft.settings.remindersEnabled = true }
        if commit(draft) {
            HapticsService.play(.taskSaved, level: state.settings.haptics)
            if task.reminder != nil { Task { await requestNotifications() } }
        }
    }

    func archiveTask(_ id: UUID) {
        if let focus = state.activeFocus, state.occurrences.contains(where: { $0.id == focus.occurrenceID && $0.taskID == id }) {
            lastError = "計測を保存してから、このタスクをアーカイブしてください。"; return
        }
        var draft = state
        draft.archiveTask(id: id)
        commit(draft)
    }

    func setMust(_ occurrenceID: UUID, _ value: Bool) {
        guard let occurrence = state.occurrences.first(where: { $0.id == occurrenceID }), occurrence.isMust != value else { return }
        var draft = state
        draft.setMust(occurrenceID: occurrenceID, value: value)
        if commit(draft) { HapticsService.play(value ? .mustPinned : .checkOff, level: state.settings.haptics) }
    }

    func setChecklistItem(occurrenceID: UUID, itemID: UUID, isDone: Bool) {
        guard let occurrence = state.occurrences.first(where: { $0.id == occurrenceID }),
              !occurrence.isCompleted,
              let item = occurrence.checklist.first(where: { $0.id == itemID }),
              item.isDone != isDone else { return }
        var draft = state
        draft.setChecklistItem(occurrenceID: occurrenceID, itemID: itemID, isDone: isDone)
        if commit(draft) {
            if isDone && draft.occurrences.first(where: { $0.id == occurrenceID })?.checklist.allSatisfy(\.isDone) == true {
                HapticsService.play(.checklistClear, level: state.settings.haptics)
            } else { HapticsService.play(isDone ? .checkOn : .checkOff, level: state.settings.haptics) }
        }
    }

    func complete(_ occurrenceID: UUID) {
        var draft = state
        guard let result = draft.complete(occurrenceID: occurrenceID, at: Date()), commit(draft) else { return }
        HapticsService.tap(level: state.settings.haptics)
        let title = state.occurrences.first { $0.id == occurrenceID }?.title ?? "タスク"
        completion = CompletionPresentation(taskTitle: title, stars: result.receipt.stars, xp: result.receipt.xp, previousXP: result.previousXP, totalXP: result.totalXP, level: result.level, didLevelUp: result.didLevelUp, newMedals: result.newMedals, occurrenceID: occurrenceID, didCompleteTodaysMust: result.didCompleteTodaysMust)
    }

    func startFocus(_ occurrenceID: UUID, mode: FocusMode, targetMinutes: Int?) {
        var draft = state
        guard draft.startFocus(occurrenceID: occurrenceID, mode: mode, targetMinutes: targetMinutes, at: Date()) else {
            lastError = "進行中の計測を保存してから、新しい計測を始めてください。"; return
        }
        if commit(draft) {
            HapticsService.play(.focusStart, level: state.settings.haptics)
            if mode == .countdown { Task { await requestNotifications() } }
        }
    }
    @discardableResult
    func pauseFocus(reachedTarget: Bool = false) -> Bool {
        guard let focus = state.activeFocus, !focus.isPaused else { return false }
        var draft = state
        draft.pauseFocus(at: Date())
        guard commit(draft) else { return false }
        HapticsService.play(reachedTarget ? .targetReached : .focusPause, level: state.settings.haptics)
        return true
    }

    func resumeFocus() {
        guard let focus = state.activeFocus, focus.isPaused else { return }
        var draft = state
        draft.resumeFocus(at: Date())
        if commit(draft) { HapticsService.play(.focusResume, level: state.settings.haptics) }
    }

    func extendFocus(minutes: Int, resumeIfPaused: Bool = false) {
        guard minutes > 0, state.activeFocus != nil else { return }
        var draft = state
        draft.extendFocus(minutes: minutes)
        if resumeIfPaused, draft.activeFocus?.isPaused == true { draft.resumeFocus(at: Date()) }
        if commit(draft) { HapticsService.play(.focusExtend, level: state.settings.haptics) }
    }

    func finishFocus(completeTask: Bool) {
        guard let focus = state.activeFocus else { return }
        if completeTask { complete(focus.occurrenceID); return }
        var draft = state
        let previousMedals = Set(draft.medals.map(\.id))
        guard let session = draft.finishFocus(at: Date()), commit(draft) else { return }
        let added = draft.medals.filter { !previousMedals.contains($0.id) }
        if !added.isEmpty {
            completion = CompletionPresentation(taskTitle: session.taskTitle, stars: 0, xp: 0, previousXP: state.totalXP, totalXP: state.totalXP, level: state.level, didLevelUp: false, newMedals: added, occurrenceID: focus.occurrenceID)
        } else { HapticsService.success(level: state.settings.haptics) }
    }

    func saveNote(occurrenceID: UUID, text: String, photos: [Data]) {
        guard state.occurrences.contains(where: { $0.id == occurrenceID }) else { lastError = "記録するタスクが見つかりません。"; return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty else { return }
        do {
            let names = try photos.map { try repository.savePhoto(jpegData($0)) }
            var draft = state
            draft.addNote(occurrenceID: occurrenceID, text: text, photoNames: names, at: Date())
            if commit(draft) { HapticsService.success(level: state.settings.haptics) }
        } catch { lastError = "写真を保存できませんでした：\(error.localizedDescription)" }
    }

    func saveTaskPhotos(_ datas: [Data]) -> [String] {
        do { return try datas.map { try repository.savePhoto(jpegData($0)) } }
        catch { lastError = "写真を保存できませんでした：\(error.localizedDescription)"; return [] }
    }
    func photoURL(_ name: String) -> URL? { repository.photoURL(name) }

    func updateSettings(_ settings: AppSettings) {
        let request = settings.remindersEnabled && !state.settings.remindersEnabled
        var draft = state
        draft.settings = settings
        if commit(draft), request { Task { await requestNotifications() } }
    }
    func addList(_ name: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !state.listNames.contains(title) else { return }
        var draft = state
        draft.listNames.append(title)
        commit(draft)
    }
    func requestNotifications() async {
        do {
            guard try await notifications.requestPermission() else {
                lastError = "通知は許可されていません。iPhoneの設定から変更できます。"; return
            }
            await notifications.reconcile(state: state)
        } catch { lastError = "通知を設定できませんでした：\(error.localizedDescription)" }
    }

    @discardableResult private func commit(_ draft: AppState) -> Bool {
        guard !persistenceBlocked else { lastError = "元データを保護するため保存を停止しています。"; return false }
        do {
            try repository.save(draft)
            state = draft
            lastError = nil
            screenTime.sync(with: draft)
            notificationTask?.cancel()
            notificationTask = Task { await notifications.reconcile(state: draft) }
            return true
        } catch { lastError = "保存できませんでした。もう一度お試しください：\(error.localizedDescription)"; return false }
    }
    private func jpegData(_ data: Data) -> Data {
        UIImage(data: data)?.jpegData(compressionQuality: 0.85) ?? data
    }
}
