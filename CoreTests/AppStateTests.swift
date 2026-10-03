import Foundation
import XCTest
@testable import DopagakiCore

final class AppStateTests: XCTestCase {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
    private func freshState(timeZone: String = "Asia/Tokyo") -> AppState {
        AppState(settings: AppSettings(aggregationTimeZoneID: timeZone))
    }
    private func task(_ title: String = "英語", at created: Date, recurrence: RecurrenceRule = .init(), deadline: Date? = nil, deadlineHasTime: Bool = false, isMust: Bool = false, checklist: [ChecklistItem] = []) -> TaskDefinition {
        TaskDefinition(title: title, recurrence: recurrence, createdAt: created, deadline: deadline, deadlineHasTime: deadlineHasTime, isMust: isMust, checklist: checklist)
    }

    func testCompletionAndReceiptAreIdempotentAcrossPersistence() throws {
        let now = date("2026-10-02T10:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: now), on: now)
        let occurrence = try XCTUnwrap(state.occurrences.first)
        let result = try XCTUnwrap(state.complete(occurrenceID: occurrence.id, at: now))
        XCTAssertEqual(result.receipt.stars, 3)
        XCTAssertEqual(result.receipt.xp, 100)
        XCTAssertEqual(result.newMedals.map(\.id), [.firstStep])
        XCTAssertNil(state.complete(occurrenceID: occurrence.id, at: now.addingTimeInterval(60)))
        var restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        XCTAssertNil(restored.complete(occurrenceID: occurrence.id, at: now))
        XCTAssertEqual(restored.totalXP, 100)
        XCTAssertEqual(restored.rewards.count, 1)
        XCTAssertEqual(restored.medals.count, 1)
    }

    func testDateOnlyDeadlineIncludesWholeDayAndRejectsNextDay() throws {
        let created = date("2026-10-01T08:00:00+09:00")
        let deadline = date("2026-10-02T00:00:00+09:00")
        var state = freshState()
        let first = task("日内", at: created, deadline: deadline)
        let second = task("翌日", at: created, deadline: deadline)
        state.saveTask(first, on: created)
        state.saveTask(second, on: created)
        let id1 = try XCTUnwrap(state.occurrences.first(where: { $0.taskID == first.id })?.id)
        let id2 = try XCTUnwrap(state.occurrences.first(where: { $0.taskID == second.id })?.id)
        XCTAssertEqual(state.complete(occurrenceID: id1, at: date("2026-10-02T23:59:59+09:00"))?.receipt.stars, 3)
        XCTAssertEqual(state.complete(occurrenceID: id2, at: date("2026-10-03T00:00:00+09:00"))?.receipt.stars, 2)
    }

    func testExplicitDeadlineRewardBoundariesAndLevelTransition() throws {
        let now = date("2026-10-02T12:00:00+09:00")
        var state = freshState()
        for lateness: Double in [0, 86_400, 86_401] {
            let definition = task("時間指定", at: now, deadline: now, deadlineHasTime: true)
            state.saveTask(definition, on: now)
            let id = try XCTUnwrap(state.occurrences.first(where: { $0.taskID == definition.id })?.id)
            let result = try XCTUnwrap(state.complete(occurrenceID: id, at: now.addingTimeInterval(lateness)))
            XCTAssertEqual(result.receipt.stars, lateness == 0 ? 3 : lateness == 86_400 ? 2 : 1)
            XCTAssertEqual(result.receipt.xp, lateness == 0 ? 100 : lateness == 86_400 ? 70 : 50)
        }
        XCTAssertEqual(state.totalXP, 220)
        XCTAssertEqual(state.level, 1)
        let definition = task(at: now)
        state.saveTask(definition, on: now)
        let id = try XCTUnwrap(state.occurrences.first(where: { $0.taskID == definition.id })?.id)
        let result = try XCTUnwrap(state.complete(occurrenceID: id, at: now))
        XCTAssertTrue(result.didLevelUp)
        XCTAssertEqual(state.level, 2)
        XCTAssertEqual(state.levelProgress, 70.0 / 250, accuracy: 0.000_001)
    }

    func testDailyOccurrencesDoNotDuplicateAndCompletedSnapshotsStayUnchanged() throws {
        let firstDay = date("2026-10-02T09:00:00+09:00")
        let secondDay = date("2026-10-03T09:00:00+09:00")
        var state = freshState()
        var definition = task("元の名前", at: firstDay, recurrence: .init(frequency: .daily), deadline: firstDay, deadlineHasTime: true, isMust: true)
        state.saveTask(definition, on: firstDay)
        let first = try XCTUnwrap(state.occurrences.first)
        state.ensureOccurrences(on: firstDay)
        XCTAssertEqual(state.occurrences.count, 1)
        _ = state.complete(occurrenceID: first.id, at: firstDay)
        definition.title = "新しい名前"
        definition.isMust = false
        state.saveTask(definition, on: secondDay)
        state.ensureOccurrences(on: secondDay)
        XCTAssertEqual(state.occurrences.count, 2)
        let snapshot = try XCTUnwrap(state.occurrences.first(where: { $0.id == first.id }))
        XCTAssertEqual(snapshot.title, "元の名前")
        XCTAssertTrue(snapshot.isMust)
        XCTAssertEqual(snapshot.deadline, first.deadline)
        let second = try XCTUnwrap(state.occurrences(on: secondDay).first)
        XCTAssertEqual(second.title, "新しい名前")
        XCTAssertFalse(second.isMust)
        XCTAssertEqual(second.deadline, secondDay)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testWeeklyAndShortMonthRecurrences() {
        let created = date("2026-01-01T09:00:00+09:00")
        var state = freshState()
        let monday = task("月曜", at: created, recurrence: .init(frequency: .weekly, weekdays: [2]))
        let monthly = task("月末", at: created, recurrence: .init(frequency: .monthly, monthDay: 31))
        state.saveTask(monday, on: created)
        state.saveTask(monthly, on: created)
        state.ensureOccurrences(on: date("2026-02-23T09:00:00+09:00"))
        state.ensureOccurrences(on: date("2026-02-24T09:00:00+09:00"))
        state.ensureOccurrences(on: date("2026-02-28T09:00:00+09:00"))
        state.ensureOccurrences(on: date("2026-03-31T09:00:00+09:00"))
        XCTAssertEqual(state.occurrences.filter { $0.taskID == monday.id }.map(\.dayKey), ["2026-02-23"])
        XCTAssertEqual(state.occurrences.filter { $0.taskID == monthly.id }.map(\.dayKey), ["2026-02-28", "2026-03-31"])
    }

    func testOverdueOneOffRemainsVisibleAndCompletingTodayKeepsItsMustStatus() throws {
        let yesterday = date("2026-10-01T08:00:00+09:00")
        let today = date("2026-10-02T08:00:00+09:00")
        let tomorrow = date("2026-10-03T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: yesterday, deadline: yesterday, isMust: true), on: yesterday)
        state.ensureOccurrences(on: today)
        let occurrence = try XCTUnwrap(state.occurrences(on: today).first)
        XCTAssertFalse(state.todaysMustComplete(on: today))
        _ = state.complete(occurrenceID: occurrence.id, at: today)
        XCTAssertEqual(state.occurrences(on: today).map(\.id), [occurrence.id])
        XCTAssertTrue(state.todaysMustComplete(on: today))
        XCTAssertTrue(state.occurrences(on: tomorrow).isEmpty)
        XCTAssertEqual(state.activity(on: today).completedCount, 1)
        XCTAssertEqual(state.activity(on: yesterday).completedCount, 0)
    }

    func testNoMustAndOptionalTasksNeverLockTheDay() throws {
        let now = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        XCTAssertTrue(state.todaysMustComplete(on: now))
        state.saveTask(task(at: now), on: now)
        XCTAssertTrue(state.todaysMustComplete(on: now))
        let occurrence = try XCTUnwrap(state.occurrences.first)
        state.setMust(occurrenceID: occurrence.id, value: true)
        XCTAssertFalse(state.todaysMustComplete(on: now))
        state.setMust(occurrenceID: occurrence.id, value: false)
        XCTAssertTrue(state.todaysMustComplete(on: now))
    }

    func testFocusPauseAndProcessRestartExcludeIdleTime() throws {
        let start = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let occurrence = try XCTUnwrap(state.occurrences.first)
        XCTAssertTrue(state.startFocus(occurrenceID: occurrence.id, mode: .stopwatch, at: start))
        XCTAssertFalse(state.startFocus(occurrenceID: occurrence.id, mode: .stopwatch, at: start))
        state.pauseFocus(at: start.addingTimeInterval(600))
        state.pauseFocus(at: start.addingTimeInterval(900))
        XCTAssertEqual(state.activeFocus?.elapsed(at: start.addingTimeInterval(1800)), 600)
        XCTAssertTrue(try XCTUnwrap(state.activeFocus).isPaused)
        state = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        state.resumeFocus(at: start.addingTimeInterval(1800))
        state.resumeFocus(at: start.addingTimeInterval(1900))
        state = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(state.activeFocus?.elapsed(at: start.addingTimeInterval(3000)), 1800)
        let session = try XCTUnwrap(state.finishFocus(at: start.addingTimeInterval(3000)))
        XCTAssertEqual(session.duration, 1800)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(state.totalSeconds, 1800)
        XCTAssertNil(state.finishFocus(at: start.addingTimeInterval(3000)))
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertFalse(try XCTUnwrap(state.occurrences.first).isCompleted)
        XCTAssertEqual(state.totalXP, 0)
    }

    func testCompletingActiveTaskSavesFocusBeforeReceipt() throws {
        let start = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let id = try XCTUnwrap(state.occurrences.first?.id)
        XCTAssertTrue(state.startFocus(occurrenceID: id, mode: .stopwatch, at: start))
        _ = state.complete(occurrenceID: id, at: start.addingTimeInterval(3600))
        XCTAssertNil(state.activeFocus)
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.totalSeconds, 3600)
        XCTAssertEqual(state.rewards.count, 1)
    }

    func testCountdownNeedsGoalExtendsAndDoesNotAutoComplete() throws {
        let start = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let id = try XCTUnwrap(state.occurrences.first?.id)
        XCTAssertFalse(state.startFocus(occurrenceID: id, mode: .countdown, at: start))
        XCTAssertTrue(state.startFocus(occurrenceID: id, mode: .countdown, targetMinutes: 15, at: start))
        state.extendFocus(minutes: 5, at: start.addingTimeInterval(300))
        XCTAssertEqual(state.activeFocus?.targetSeconds, 1200)
        XCTAssertEqual(state.activeFocus?.elapsed(at: start.addingTimeInterval(1500)), 1200)
        _ = state.finishFocus(at: start.addingTimeInterval(1500))
        XCTAssertEqual(state.totalSeconds, 1200)
        XCTAssertFalse(try XCTUnwrap(state.occurrences.first).isCompleted)
    }

    func testMidnightSplitUsesRunningIntervalsOnly() throws {
        let start = date("2026-10-02T23:50:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let id = try XCTUnwrap(state.occurrences.first?.id)
        XCTAssertTrue(state.startFocus(occurrenceID: id, mode: .stopwatch, at: start))
        state.pauseFocus(at: date("2026-10-02T23:55:00+09:00"))
        state.resumeFocus(at: date("2026-10-03T00:05:00+09:00"))
        _ = state.finishFocus(at: date("2026-10-03T00:15:00+09:00"))
        XCTAssertEqual(state.activity(on: start).seconds, 300)
        XCTAssertEqual(state.activity(on: date("2026-10-03T12:00:00+09:00")).seconds, 600)
        XCTAssertEqual(state.totalSeconds, 900)
        XCTAssertEqual(state.currentStreak(at: date("2026-10-03T12:00:00+09:00")), 2)
    }

    func testCountdownBackgroundExpiryAndExtensionExcludeAbandonedTime() throws {
        let start = date("2026-10-02T23:55:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let id = try XCTUnwrap(state.occurrences.first?.id)
        XCTAssertTrue(state.startFocus(occurrenceID: id, mode: .countdown, targetMinutes: 15, at: start))
        let returned = start.addingTimeInterval(3 * 3600)
        state = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(state.activeFocus?.elapsed(at: returned), 900)
        state.extendFocus(minutes: 5, at: returned)
        XCTAssertTrue(try XCTUnwrap(state.activeFocus).isPaused)
        XCTAssertEqual(state.activeFocus?.targetSeconds, 1200)
        XCTAssertEqual(state.activeFocus?.accumulatedSeconds, 900)
        // Another long pause after extension is excluded until the explicit resume.
        let resumed = returned.addingTimeInterval(3600)
        state.resumeFocus(at: resumed)
        state.pauseFocus(at: resumed.addingTimeInterval(60))
        XCTAssertEqual(state.activeFocus?.accumulatedSeconds, 960)
        state.resumeFocus(at: resumed.addingTimeInterval(120))
        let session = try XCTUnwrap(state.finishFocus(at: resumed.addingTimeInterval(3600)))
        XCTAssertEqual(session.duration, 1200)
        XCTAssertEqual(state.activity(on: start).seconds, 300)
        XCTAssertEqual(state.activity(on: returned).seconds, 900)
        XCTAssertFalse(try XCTUnwrap(state.occurrences.first).isCompleted)

        // Saving an expired timer directly is also capped at its target.
        XCTAssertTrue(state.startFocus(occurrenceID: id, mode: .countdown, targetMinutes: 5, at: resumed))
        let direct = try XCTUnwrap(state.finishFocus(at: resumed.addingTimeInterval(7200)))
        XCTAssertEqual(direct.duration, 300)
    }

    func testDSTDayBoundaryAndFixedTimeZone() throws {
        var state = freshState(timeZone: "America/Los_Angeles")
        let start = date("2026-03-08T00:00:00-08:00")
        let end = date("2026-03-09T00:00:00-07:00")
        state.sessions = [FocusSession(startedAt: start, endedAt: end, segments: [FocusSegment(start: start, end: end)])]
        XCTAssertEqual(state.activity(on: start).seconds, 23 * 3600)
        XCTAssertEqual(state.activity(on: end).seconds, 0)
        XCTAssertEqual(state.dayKey(for: date("2026-03-09T15:00:00+09:00")), "2026-03-08")
        state = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(state.settings.aggregationTimeZoneID, "America/Los_Angeles")
        XCTAssertEqual(state.activity(on: start).seconds, 23 * 3600)
    }

    func testStreakYesterdayGraceAndMedalsNeverRetract() throws {
        let start = date("2026-09-01T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start, recurrence: .init(frequency: .daily)), on: start)
        for offset in 0..<7 {
            let day = state.calendar.date(byAdding: .day, value: offset, to: start)!
            state.ensureOccurrences(on: day)
            let id = try XCTUnwrap(state.occurrences(on: day).first?.id)
            _ = state.complete(occurrenceID: id, at: day)
        }
        XCTAssertEqual(state.currentStreak(at: date("2026-09-08T08:00:00+09:00")), 7)
        XCTAssertEqual(state.currentStreak(at: date("2026-09-09T08:00:00+09:00")), 0)
        XCTAssertEqual(state.longestStreak(), 7)
        XCTAssertTrue(state.medals.contains(where: { $0.id == .weekStreak }))
        let comebackDay = date("2026-09-10T08:00:00+09:00")
        state.ensureOccurrences(on: comebackDay)
        let id = try XCTUnwrap(state.occurrences(on: comebackDay).first?.id)
        let result = try XCTUnwrap(state.complete(occurrenceID: id, at: comebackDay))
        XCTAssertTrue(result.newMedals.contains(where: { $0.id == .comeback }))
        XCTAssertEqual(state.currentStreak(at: comebackDay), 1)
        XCTAssertTrue(state.medals.contains(where: { $0.id == .weekStreak }))
    }

    func testGrassIntensityIncludesSubMinuteAndUntimedCompletionAndNoFuture() throws {
        let today = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        XCTAssertEqual(state.activity(on: today).intensity, 0)
        state.saveTask(task(at: today), on: today)
        let id = try XCTUnwrap(state.occurrences.first?.id)
        _ = state.complete(occurrenceID: id, at: today)
        XCTAssertEqual(state.activity(on: today).intensity, 1)
        for (seconds, expected) in [(1.0, 1), (899, 1), (900, 2), (1800, 3), (3600, 4)] {
            state.sessions = [FocusSession(occurrenceID: id, startedAt: today, endedAt: today.addingTimeInterval(seconds), segments: [FocusSegment(start: today, end: today.addingTimeInterval(seconds))])]
            XCTAssertEqual(state.activity(on: today).intensity, expected)
        }
        let grid = state.activityDays(ending: today)
        XCTAssertEqual(grid.count, 90)
        XCTAssertEqual(state.calendar.component(.weekday, from: try XCTUnwrap(grid.first?.date)), 1)
        XCTAssertEqual(grid.last?.dayKey, "2026-10-02")
        XCTAssertTrue(grid.allSatisfy { $0.date <= today })
        XCTAssertTrue(state.activityDays(ending: today, weeks: 0).isEmpty)
    }

    func testDailyChecklistIsIndependentAndEditingPreservesProgress() throws {
        let firstDay = date("2026-10-02T08:00:00+09:00")
        let nextDay = date("2026-10-03T08:00:00+09:00")
        let keep = ChecklistItem(title: "単語", isDone: true)
        let removed = ChecklistItem(title: "文法")
        var state = freshState()
        var definition = task(at: firstDay, recurrence: .init(frequency: .daily), checklist: [keep, removed])
        state.saveTask(definition, on: firstDay)
        let first = try XCTUnwrap(state.occurrences.first)
        XCTAssertFalse(first.checklist[0].isDone)
        state.setChecklistItem(occurrenceID: first.id, itemID: keep.id, isDone: true)
        let added = ChecklistItem(title: "発音", isDone: true)
        definition.checklist = [ChecklistItem(id: keep.id, title: "英単語"), added]
        state.saveTask(definition, on: firstDay)
        let edited = try XCTUnwrap(state.occurrences.first)
        XCTAssertEqual(edited.checklist.map(\.title), ["英単語", "発音"])
        XCTAssertTrue(edited.checklist[0].isDone)
        XCTAssertFalse(edited.checklist[1].isDone)
        _ = state.complete(occurrenceID: first.id, at: firstDay)
        state.setChecklistItem(occurrenceID: first.id, itemID: keep.id, isDone: false)
        state.ensureOccurrences(on: nextDay)
        let next = try XCTUnwrap(state.occurrences(on: nextDay).first)
        XCTAssertTrue(next.checklist.allSatisfy { !$0.isDone })
        XCTAssertTrue(try XCTUnwrap(state.occurrences.first(where: { $0.id == first.id })).checklist[0].isDone)
    }

    func testSessionMilestonesAndEmptyNotes() throws {
        let start = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let id = try XCTUnwrap(state.occurrences.first?.id)
        state.addNote(occurrenceID: id, text: "  \n ", at: start)
        XCTAssertTrue(state.notes.isEmpty)
        state.addNote(occurrenceID: id, text: " 学んだ ", photoNames: ["photo.jpg"], at: start)
        XCTAssertEqual(state.notes.first?.text, "学んだ")
        XCTAssertTrue(state.startFocus(occurrenceID: id, mode: .stopwatch, at: start))
        _ = state.finishFocus(at: start.addingTimeInterval(10 * 3600))
        XCTAssertTrue(state.medals.contains(where: { $0.id == .tenHours }))
        XCTAssertFalse(state.medals.contains(where: { $0.id == .firstStep }))
        state.archiveTask(id: try XCTUnwrap(state.tasks.first?.id))
        XCTAssertTrue(state.occurrences(on: start).isEmpty)
        XCTAssertFalse(state.startFocus(occurrenceID: id, mode: .stopwatch, at: start))
        XCTAssertEqual(state.activity(on: start).seconds, 10 * 3600)
    }

    func testMustFinaleOnlyForLastPendingMustAndNeverDuplicates() throws {
        let now = date("2026-10-02T10:00:00+09:00")
        var state = freshState()
        state.saveTask(task("マスト1", at: now, isMust: true), on: now)
        state.saveTask(task("マスト2", at: now, isMust: true), on: now)
        state.saveTask(task("任意", at: now), on: now)
        let musts = state.occurrences.filter(\.isMust)
        let optional = try XCTUnwrap(state.occurrences.first { !$0.isMust })
        XCTAssertFalse(try XCTUnwrap(state.complete(occurrenceID: musts[0].id, at: now)).didCompleteTodaysMust)
        let final = try XCTUnwrap(state.complete(occurrenceID: musts[1].id, at: now))
        XCTAssertTrue(final.didCompleteTodaysMust)
        XCTAssertEqual(final.receipt.xp, 100) // The finale is visual, not an extra reward.
        var restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertNil(restored.complete(occurrenceID: musts[1].id, at: now))
        XCTAssertFalse(try XCTUnwrap(restored.complete(occurrenceID: optional.id, at: now)).didCompleteTodaysMust)
        XCTAssertEqual(restored.totalXP, 300)
        var noMusts = freshState()
        noMusts.saveTask(task(at: now), on: now)
        let id = try XCTUnwrap(noMusts.occurrences.first?.id)
        XCTAssertFalse(try XCTUnwrap(noMusts.complete(occurrenceID: id, at: now)).didCompleteTodaysMust)
    }

    func testMustFinaleRespectsRolloverAndOverdueTasks() throws {
        let yesterday = date("2026-10-01T10:00:00+09:00")
        let today = date("2026-10-02T10:00:00+09:00")
        var state = freshState()
        let repeating = task("毎日のマスト", at: yesterday, recurrence: .init(frequency: .daily), isMust: true)
        state.saveTask(repeating, on: yesterday)
        let past = try XCTUnwrap(state.occurrences.first?.id)
        // Completion must materialize today's recurrence even before a UI refresh.
        XCTAssertFalse(try XCTUnwrap(state.complete(occurrenceID: past, at: today)).didCompleteTodaysMust)
        let current = try XCTUnwrap(state.occurrences.first { $0.dayKey == state.dayKey(for: today) })
        let overdue = task("持ち越し", at: yesterday, isMust: true)
        state.saveTask(overdue, on: today)
        XCTAssertFalse(try XCTUnwrap(state.complete(occurrenceID: current.id, at: today)).didCompleteTodaysMust)
        let last = try XCTUnwrap(state.occurrences.first { $0.taskID == overdue.id })
        XCTAssertTrue(try XCTUnwrap(state.complete(occurrenceID: last.id, at: today)).didCompleteTodaysMust)
        let tomorrow = date("2026-10-03T10:00:00+09:00")
        state.ensureOccurrences(on: tomorrow)
        let next = try XCTUnwrap(state.occurrences.first { $0.dayKey == state.dayKey(for: tomorrow) })
        XCTAssertTrue(try XCTUnwrap(state.complete(occurrenceID: next.id, at: tomorrow)).didCompleteTodaysMust)
    }

    func testLevelFillHoldsFullBarBeforeCarryingXP() {
        let crossing = LevelFillStep.steps(from: 200, to: 300)
        XCTAssertEqual(crossing.map(\.level), [1, 2])
        XCTAssertEqual(crossing.map(\.fromXP), [200, 0])
        XCTAssertEqual(crossing.map(\.toXP), [250, 50])
        XCTAssertEqual(crossing.map(\.reachesNextLevel), [true, false])
        XCTAssertEqual(crossing.reduce(0) { $0 + $1.toXP - $1.fromXP }, 100)
        let exact = LevelFillStep.steps(from: 150, to: 250)
        XCTAssertEqual(exact.count, 1)
        XCTAssertEqual(exact.first?.toXP, 250)
        XCTAssertEqual(exact.first?.reachesNextLevel, true)
        XCTAssertEqual(LevelFillStep.steps(from: 250, to: 350).first?.level, 2)
        XCTAssertEqual(LevelFillStep.steps(from: 0, to: 100).first?.toXP, 100)
        XCTAssertTrue(LevelFillStep.steps(from: 250, to: 250).isEmpty)
        XCTAssertTrue(LevelFillStep.steps(from: 300, to: 200).isEmpty)
        var state = freshState()
        XCTAssertEqual(state.xpToNextLevel, 250)
        state.rewards = [RewardReceipt(xp: 200)]
        XCTAssertEqual(state.xpToNextLevel, 50)
        state.rewards = [RewardReceipt(xp: 250)]
        XCTAssertEqual(state.xpToNextLevel, 250)
    }

}
