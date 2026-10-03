// Executable behavior checks for environments without the XCTest framework.
// The equivalent XCTest cases live in CoreTests/AppStateTests.swift.
import Foundation
import DopagakiCore
private func coreFail(_ message: String, file: StaticString = #file, line: UInt = #line) -> Never { fatalError(message, file: file, line: line) }
private func coreAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { if a != b { coreFail("Expected equal: \(a) != \(b)", file: file, line: line) } }
private func coreAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) { if abs(a-b) > accuracy { coreFail("Expected equal within accuracy: \(a) != \(b)", file: file, line: line) } }
private func coreAssertTrue(_ a: Bool, file: StaticString = #file, line: UInt = #line) { if !a { coreFail("Expected true", file: file, line: line) } }
private func coreAssertFalse(_ a: Bool, file: StaticString = #file, line: UInt = #line) { if a { coreFail("Expected false", file: file, line: line) } }
private func coreAssertNil<T>(_ a: T?, file: StaticString = #file, line: UInt = #line) { if a != nil { coreFail("Expected nil", file: file, line: line) } }
private func coreAssertNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { if a == b { coreFail("Expected different values", file: file, line: line) } }
private struct UnwrapFailure: Error {}
private func coreUnwrap<T>(_ a: T?) throws -> T { guard let value = a else { throw UnwrapFailure() }; return value }


private final class CoreBehaviorChecks {
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
        let occurrence = try coreUnwrap(state.occurrences.first)
        let result = try coreUnwrap(state.complete(occurrenceID: occurrence.id, at: now))
        coreAssertEqual(result.receipt.stars, 3)
        coreAssertEqual(result.receipt.xp, 100)
        coreAssertEqual(result.newMedals.map(\.id), [.firstStep])
        coreAssertNil(state.complete(occurrenceID: occurrence.id, at: now.addingTimeInterval(60)))
        var restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        coreAssertEqual(restored, state)
        coreAssertNil(restored.complete(occurrenceID: occurrence.id, at: now))
        coreAssertEqual(restored.totalXP, 100)
        coreAssertEqual(restored.rewards.count, 1)
        coreAssertEqual(restored.medals.count, 1)
    }

    func testDateOnlyDeadlineIncludesWholeDayAndRejectsNextDay() throws {
        let created = date("2026-10-01T08:00:00+09:00")
        let deadline = date("2026-10-02T00:00:00+09:00")
        var state = freshState()
        let first = task("日内", at: created, deadline: deadline)
        let second = task("翌日", at: created, deadline: deadline)
        state.saveTask(first, on: created)
        state.saveTask(second, on: created)
        let id1 = try coreUnwrap(state.occurrences.first(where: { $0.taskID == first.id })?.id)
        let id2 = try coreUnwrap(state.occurrences.first(where: { $0.taskID == second.id })?.id)
        coreAssertEqual(state.complete(occurrenceID: id1, at: date("2026-10-02T23:59:59+09:00"))?.receipt.stars, 3)
        coreAssertEqual(state.complete(occurrenceID: id2, at: date("2026-10-03T00:00:00+09:00"))?.receipt.stars, 2)
    }

    func testExplicitDeadlineRewardBoundariesAndLevelTransition() throws {
        let now = date("2026-10-02T12:00:00+09:00")
        var state = freshState()
        for lateness: Double in [0, 86_400, 86_401] {
            let definition = task("時間指定", at: now, deadline: now, deadlineHasTime: true)
            state.saveTask(definition, on: now)
            let id = try coreUnwrap(state.occurrences.first(where: { $0.taskID == definition.id })?.id)
            let result = try coreUnwrap(state.complete(occurrenceID: id, at: now.addingTimeInterval(lateness)))
            coreAssertEqual(result.receipt.stars, lateness == 0 ? 3 : lateness == 86_400 ? 2 : 1)
            coreAssertEqual(result.receipt.xp, lateness == 0 ? 100 : lateness == 86_400 ? 70 : 50)
        }
        coreAssertEqual(state.totalXP, 220)
        coreAssertEqual(state.level, 1)
        let definition = task(at: now)
        state.saveTask(definition, on: now)
        let id = try coreUnwrap(state.occurrences.first(where: { $0.taskID == definition.id })?.id)
        let result = try coreUnwrap(state.complete(occurrenceID: id, at: now))
        coreAssertTrue(result.didLevelUp)
        coreAssertEqual(state.level, 2)
        coreAssertEqual(state.levelProgress, 70.0 / 250, accuracy: 0.000_001)
    }

    func testDailyOccurrencesDoNotDuplicateAndCompletedSnapshotsStayUnchanged() throws {
        let firstDay = date("2026-10-02T09:00:00+09:00")
        let secondDay = date("2026-10-03T09:00:00+09:00")
        var state = freshState()
        var definition = task("元の名前", at: firstDay, recurrence: .init(frequency: .daily), deadline: firstDay, deadlineHasTime: true, isMust: true)
        state.saveTask(definition, on: firstDay)
        let first = try coreUnwrap(state.occurrences.first)
        state.ensureOccurrences(on: firstDay)
        coreAssertEqual(state.occurrences.count, 1)
        _ = state.complete(occurrenceID: first.id, at: firstDay)
        definition.title = "新しい名前"
        definition.isMust = false
        state.saveTask(definition, on: secondDay)
        state.ensureOccurrences(on: secondDay)
        coreAssertEqual(state.occurrences.count, 2)
        let snapshot = try coreUnwrap(state.occurrences.first(where: { $0.id == first.id }))
        coreAssertEqual(snapshot.title, "元の名前")
        coreAssertTrue(snapshot.isMust)
        coreAssertEqual(snapshot.deadline, first.deadline)
        let second = try coreUnwrap(state.occurrences(on: secondDay).first)
        coreAssertEqual(second.title, "新しい名前")
        coreAssertFalse(second.isMust)
        coreAssertEqual(second.deadline, secondDay)
        coreAssertNotEqual(first.id, second.id)
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
        coreAssertEqual(state.occurrences.filter { $0.taskID == monday.id }.map(\.dayKey), ["2026-02-23"])
        coreAssertEqual(state.occurrences.filter { $0.taskID == monthly.id }.map(\.dayKey), ["2026-02-28", "2026-03-31"])
    }

    func testOverdueOneOffRemainsVisibleAndCompletingTodayKeepsItsMustStatus() throws {
        let yesterday = date("2026-10-01T08:00:00+09:00")
        let today = date("2026-10-02T08:00:00+09:00")
        let tomorrow = date("2026-10-03T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: yesterday, deadline: yesterday, isMust: true), on: yesterday)
        state.ensureOccurrences(on: today)
        let occurrence = try coreUnwrap(state.occurrences(on: today).first)
        coreAssertFalse(state.todaysMustComplete(on: today))
        _ = state.complete(occurrenceID: occurrence.id, at: today)
        coreAssertEqual(state.occurrences(on: today).map(\.id), [occurrence.id])
        coreAssertTrue(state.todaysMustComplete(on: today))
        coreAssertTrue(state.occurrences(on: tomorrow).isEmpty)
        coreAssertEqual(state.activity(on: today).completedCount, 1)
        coreAssertEqual(state.activity(on: yesterday).completedCount, 0)
    }

    func testNoMustAndOptionalTasksNeverLockTheDay() throws {
        let now = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        coreAssertTrue(state.todaysMustComplete(on: now))
        state.saveTask(task(at: now), on: now)
        coreAssertTrue(state.todaysMustComplete(on: now))
        let occurrence = try coreUnwrap(state.occurrences.first)
        state.setMust(occurrenceID: occurrence.id, value: true)
        coreAssertFalse(state.todaysMustComplete(on: now))
        state.setMust(occurrenceID: occurrence.id, value: false)
        coreAssertTrue(state.todaysMustComplete(on: now))
    }

    func testFocusPauseAndProcessRestartExcludeIdleTime() throws {
        let start = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let occurrence = try coreUnwrap(state.occurrences.first)
        coreAssertTrue(state.startFocus(occurrenceID: occurrence.id, mode: .stopwatch, at: start))
        coreAssertFalse(state.startFocus(occurrenceID: occurrence.id, mode: .stopwatch, at: start))
        state.pauseFocus(at: start.addingTimeInterval(600))
        state.pauseFocus(at: start.addingTimeInterval(900))
        coreAssertEqual(state.activeFocus?.elapsed(at: start.addingTimeInterval(1800)), 600)
        coreAssertTrue(try coreUnwrap(state.activeFocus).isPaused)
        state = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        state.resumeFocus(at: start.addingTimeInterval(1800))
        state.resumeFocus(at: start.addingTimeInterval(1900))
        state = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        coreAssertEqual(state.activeFocus?.elapsed(at: start.addingTimeInterval(3000)), 1800)
        let session = try coreUnwrap(state.finishFocus(at: start.addingTimeInterval(3000)))
        coreAssertEqual(session.duration, 1800)
        coreAssertEqual(session.segments.count, 2)
        coreAssertEqual(state.totalSeconds, 1800)
        coreAssertNil(state.finishFocus(at: start.addingTimeInterval(3000)))
        coreAssertEqual(state.sessions.count, 1)
        coreAssertFalse(try coreUnwrap(state.occurrences.first).isCompleted)
        coreAssertEqual(state.totalXP, 0)
    }

    func testCompletingActiveTaskSavesFocusBeforeReceipt() throws {
        let start = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let id = try coreUnwrap(state.occurrences.first?.id)
        coreAssertTrue(state.startFocus(occurrenceID: id, mode: .stopwatch, at: start))
        _ = state.complete(occurrenceID: id, at: start.addingTimeInterval(3600))
        coreAssertNil(state.activeFocus)
        coreAssertEqual(state.sessions.count, 1)
        coreAssertEqual(state.totalSeconds, 3600)
        coreAssertEqual(state.rewards.count, 1)
    }

    func testCountdownNeedsGoalExtendsAndDoesNotAutoComplete() throws {
        let start = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let id = try coreUnwrap(state.occurrences.first?.id)
        coreAssertFalse(state.startFocus(occurrenceID: id, mode: .countdown, at: start))
        coreAssertTrue(state.startFocus(occurrenceID: id, mode: .countdown, targetMinutes: 15, at: start))
        state.extendFocus(minutes: 5, at: start.addingTimeInterval(300))
        coreAssertEqual(state.activeFocus?.targetSeconds, 1200)
        coreAssertEqual(state.activeFocus?.elapsed(at: start.addingTimeInterval(1500)), 1200)
        _ = state.finishFocus(at: start.addingTimeInterval(1500))
        coreAssertEqual(state.totalSeconds, 1200)
        coreAssertFalse(try coreUnwrap(state.occurrences.first).isCompleted)
    }

    func testMidnightSplitUsesRunningIntervalsOnly() throws {
        let start = date("2026-10-02T23:50:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let id = try coreUnwrap(state.occurrences.first?.id)
        coreAssertTrue(state.startFocus(occurrenceID: id, mode: .stopwatch, at: start))
        state.pauseFocus(at: date("2026-10-02T23:55:00+09:00"))
        state.resumeFocus(at: date("2026-10-03T00:05:00+09:00"))
        _ = state.finishFocus(at: date("2026-10-03T00:15:00+09:00"))
        coreAssertEqual(state.activity(on: start).seconds, 300)
        coreAssertEqual(state.activity(on: date("2026-10-03T12:00:00+09:00")).seconds, 600)
        coreAssertEqual(state.totalSeconds, 900)
        coreAssertEqual(state.currentStreak(at: date("2026-10-03T12:00:00+09:00")), 2)
    }

    func testCountdownBackgroundExpiryAndExtensionExcludeAbandonedTime() throws {
        let start = date("2026-10-02T23:55:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let id = try coreUnwrap(state.occurrences.first?.id)
        coreAssertTrue(state.startFocus(occurrenceID: id, mode: .countdown, targetMinutes: 15, at: start))
        let returned = start.addingTimeInterval(3 * 3600)
        state = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        coreAssertEqual(state.activeFocus?.elapsed(at: returned), 900)
        state.extendFocus(minutes: 5, at: returned)
        coreAssertTrue(try coreUnwrap(state.activeFocus).isPaused)
        coreAssertEqual(state.activeFocus?.targetSeconds, 1200)
        coreAssertEqual(state.activeFocus?.accumulatedSeconds, 900)
        // Another long pause after extension is excluded until the explicit resume.
        let resumed = returned.addingTimeInterval(3600)
        state.resumeFocus(at: resumed)
        state.pauseFocus(at: resumed.addingTimeInterval(60))
        coreAssertEqual(state.activeFocus?.accumulatedSeconds, 960)
        state.resumeFocus(at: resumed.addingTimeInterval(120))
        let session = try coreUnwrap(state.finishFocus(at: resumed.addingTimeInterval(3600)))
        coreAssertEqual(session.duration, 1200)
        coreAssertEqual(state.activity(on: start).seconds, 300)
        coreAssertEqual(state.activity(on: returned).seconds, 900)
        coreAssertFalse(try coreUnwrap(state.occurrences.first).isCompleted)

        // Saving an expired timer directly is also capped at its target.
        coreAssertTrue(state.startFocus(occurrenceID: id, mode: .countdown, targetMinutes: 5, at: resumed))
        let direct = try coreUnwrap(state.finishFocus(at: resumed.addingTimeInterval(7200)))
        coreAssertEqual(direct.duration, 300)
    }

    func testDSTDayBoundaryAndFixedTimeZone() throws {
        var state = freshState(timeZone: "America/Los_Angeles")
        let start = date("2026-03-08T00:00:00-08:00")
        let end = date("2026-03-09T00:00:00-07:00")
        state.sessions = [FocusSession(startedAt: start, endedAt: end, segments: [FocusSegment(start: start, end: end)])]
        coreAssertEqual(state.activity(on: start).seconds, 23 * 3600)
        coreAssertEqual(state.activity(on: end).seconds, 0)
        coreAssertEqual(state.dayKey(for: date("2026-03-09T15:00:00+09:00")), "2026-03-08")
        state = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        coreAssertEqual(state.settings.aggregationTimeZoneID, "America/Los_Angeles")
        coreAssertEqual(state.activity(on: start).seconds, 23 * 3600)
    }

    func testStreakYesterdayGraceAndMedalsNeverRetract() throws {
        let start = date("2026-09-01T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start, recurrence: .init(frequency: .daily)), on: start)
        for offset in 0..<7 {
            let day = state.calendar.date(byAdding: .day, value: offset, to: start)!
            state.ensureOccurrences(on: day)
            let id = try coreUnwrap(state.occurrences(on: day).first?.id)
            _ = state.complete(occurrenceID: id, at: day)
        }
        coreAssertEqual(state.currentStreak(at: date("2026-09-08T08:00:00+09:00")), 7)
        coreAssertEqual(state.currentStreak(at: date("2026-09-09T08:00:00+09:00")), 0)
        coreAssertEqual(state.longestStreak(), 7)
        coreAssertTrue(state.medals.contains(where: { $0.id == .weekStreak }))
        let comebackDay = date("2026-09-10T08:00:00+09:00")
        state.ensureOccurrences(on: comebackDay)
        let id = try coreUnwrap(state.occurrences(on: comebackDay).first?.id)
        let result = try coreUnwrap(state.complete(occurrenceID: id, at: comebackDay))
        coreAssertTrue(result.newMedals.contains(where: { $0.id == .comeback }))
        coreAssertEqual(state.currentStreak(at: comebackDay), 1)
        coreAssertTrue(state.medals.contains(where: { $0.id == .weekStreak }))
    }

    func testGrassIntensityIncludesSubMinuteAndUntimedCompletionAndNoFuture() throws {
        let today = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        coreAssertEqual(state.activity(on: today).intensity, 0)
        state.saveTask(task(at: today), on: today)
        let id = try coreUnwrap(state.occurrences.first?.id)
        _ = state.complete(occurrenceID: id, at: today)
        coreAssertEqual(state.activity(on: today).intensity, 1)
        for (seconds, expected) in [(1.0, 1), (899, 1), (900, 2), (1800, 3), (3600, 4)] {
            state.sessions = [FocusSession(occurrenceID: id, startedAt: today, endedAt: today.addingTimeInterval(seconds), segments: [FocusSegment(start: today, end: today.addingTimeInterval(seconds))])]
            coreAssertEqual(state.activity(on: today).intensity, expected)
        }
        let grid = state.activityDays(ending: today)
        coreAssertEqual(grid.count, 90)
        coreAssertEqual(state.calendar.component(.weekday, from: try coreUnwrap(grid.first?.date)), 1)
        coreAssertEqual(grid.last?.dayKey, "2026-10-02")
        coreAssertTrue(grid.allSatisfy { $0.date <= today })
        coreAssertTrue(state.activityDays(ending: today, weeks: 0).isEmpty)
    }

    func testDailyChecklistIsIndependentAndEditingPreservesProgress() throws {
        let firstDay = date("2026-10-02T08:00:00+09:00")
        let nextDay = date("2026-10-03T08:00:00+09:00")
        let keep = ChecklistItem(title: "単語", isDone: true)
        let removed = ChecklistItem(title: "文法")
        var state = freshState()
        var definition = task(at: firstDay, recurrence: .init(frequency: .daily), checklist: [keep, removed])
        state.saveTask(definition, on: firstDay)
        let first = try coreUnwrap(state.occurrences.first)
        coreAssertFalse(first.checklist[0].isDone)
        state.setChecklistItem(occurrenceID: first.id, itemID: keep.id, isDone: true)
        let added = ChecklistItem(title: "発音", isDone: true)
        definition.checklist = [ChecklistItem(id: keep.id, title: "英単語"), added]
        state.saveTask(definition, on: firstDay)
        let edited = try coreUnwrap(state.occurrences.first)
        coreAssertEqual(edited.checklist.map(\.title), ["英単語", "発音"])
        coreAssertTrue(edited.checklist[0].isDone)
        coreAssertFalse(edited.checklist[1].isDone)
        _ = state.complete(occurrenceID: first.id, at: firstDay)
        state.setChecklistItem(occurrenceID: first.id, itemID: keep.id, isDone: false)
        state.ensureOccurrences(on: nextDay)
        let next = try coreUnwrap(state.occurrences(on: nextDay).first)
        coreAssertTrue(next.checklist.allSatisfy { !$0.isDone })
        coreAssertTrue(try coreUnwrap(state.occurrences.first(where: { $0.id == first.id })).checklist[0].isDone)
    }

    func testSessionMilestonesAndEmptyNotes() throws {
        let start = date("2026-10-02T08:00:00+09:00")
        var state = freshState()
        state.saveTask(task(at: start), on: start)
        let id = try coreUnwrap(state.occurrences.first?.id)
        state.addNote(occurrenceID: id, text: "  \n ", at: start)
        coreAssertTrue(state.notes.isEmpty)
        state.addNote(occurrenceID: id, text: " 学んだ ", photoNames: ["photo.jpg"], at: start)
        coreAssertEqual(state.notes.first?.text, "学んだ")
        coreAssertTrue(state.startFocus(occurrenceID: id, mode: .stopwatch, at: start))
        _ = state.finishFocus(at: start.addingTimeInterval(10 * 3600))
        coreAssertTrue(state.medals.contains(where: { $0.id == .tenHours }))
        coreAssertFalse(state.medals.contains(where: { $0.id == .firstStep }))
        state.archiveTask(id: try coreUnwrap(state.tasks.first?.id))
        coreAssertTrue(state.occurrences(on: start).isEmpty)
        coreAssertFalse(state.startFocus(occurrenceID: id, mode: .stopwatch, at: start))
        coreAssertEqual(state.activity(on: start).seconds, 10 * 3600)
    }

    func testMustFinaleOnlyForLastPendingMustAndNeverDuplicates() throws {
        let now = date("2026-10-02T10:00:00+09:00")
        var state = freshState()
        state.saveTask(task("マスト1", at: now, isMust: true), on: now)
        state.saveTask(task("マスト2", at: now, isMust: true), on: now)
        state.saveTask(task("任意", at: now), on: now)
        let musts = state.occurrences.filter(\.isMust)
        let optional = try coreUnwrap(state.occurrences.first { !$0.isMust })
        coreAssertFalse(try coreUnwrap(state.complete(occurrenceID: musts[0].id, at: now)).didCompleteTodaysMust)
        let final = try coreUnwrap(state.complete(occurrenceID: musts[1].id, at: now))
        coreAssertTrue(final.didCompleteTodaysMust)
        coreAssertEqual(final.receipt.xp, 100) // The finale is visual, not an extra reward.
        var restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        coreAssertNil(restored.complete(occurrenceID: musts[1].id, at: now))
        coreAssertFalse(try coreUnwrap(restored.complete(occurrenceID: optional.id, at: now)).didCompleteTodaysMust)
        coreAssertEqual(restored.totalXP, 300)
        var noMusts = freshState()
        noMusts.saveTask(task(at: now), on: now)
        let id = try coreUnwrap(noMusts.occurrences.first?.id)
        coreAssertFalse(try coreUnwrap(noMusts.complete(occurrenceID: id, at: now)).didCompleteTodaysMust)
    }

    func testMustFinaleRespectsRolloverAndOverdueTasks() throws {
        let yesterday = date("2026-10-01T10:00:00+09:00")
        let today = date("2026-10-02T10:00:00+09:00")
        var state = freshState()
        let repeating = task("毎日のマスト", at: yesterday, recurrence: .init(frequency: .daily), isMust: true)
        state.saveTask(repeating, on: yesterday)
        let past = try coreUnwrap(state.occurrences.first?.id)
        // Completion must materialize today's recurrence even before a UI refresh.
        coreAssertFalse(try coreUnwrap(state.complete(occurrenceID: past, at: today)).didCompleteTodaysMust)
        let current = try coreUnwrap(state.occurrences.first { $0.dayKey == state.dayKey(for: today) })
        let overdue = task("持ち越し", at: yesterday, isMust: true)
        state.saveTask(overdue, on: today)
        coreAssertFalse(try coreUnwrap(state.complete(occurrenceID: current.id, at: today)).didCompleteTodaysMust)
        let last = try coreUnwrap(state.occurrences.first { $0.taskID == overdue.id })
        coreAssertTrue(try coreUnwrap(state.complete(occurrenceID: last.id, at: today)).didCompleteTodaysMust)
        let tomorrow = date("2026-10-03T10:00:00+09:00")
        state.ensureOccurrences(on: tomorrow)
        let next = try coreUnwrap(state.occurrences.first { $0.dayKey == state.dayKey(for: tomorrow) })
        coreAssertTrue(try coreUnwrap(state.complete(occurrenceID: next.id, at: tomorrow)).didCompleteTodaysMust)
    }

    func testLevelFillHoldsFullBarBeforeCarryingXP() {
        let crossing = LevelFillStep.steps(from: 200, to: 300)
        coreAssertEqual(crossing.map(\.level), [1, 2])
        coreAssertEqual(crossing.map(\.fromXP), [200, 0])
        coreAssertEqual(crossing.map(\.toXP), [250, 50])
        coreAssertEqual(crossing.map(\.reachesNextLevel), [true, false])
        coreAssertEqual(crossing.reduce(0) { $0 + $1.toXP - $1.fromXP }, 100)
        let exact = LevelFillStep.steps(from: 150, to: 250)
        coreAssertEqual(exact.count, 1)
        coreAssertEqual(exact.first?.toXP, 250)
        coreAssertEqual(exact.first?.reachesNextLevel, true)
        coreAssertEqual(LevelFillStep.steps(from: 250, to: 350).first?.level, 2)
        coreAssertEqual(LevelFillStep.steps(from: 0, to: 100).first?.toXP, 100)
        coreAssertTrue(LevelFillStep.steps(from: 250, to: 250).isEmpty)
        coreAssertTrue(LevelFillStep.steps(from: 300, to: 200).isEmpty)
        var state = freshState()
        coreAssertEqual(state.xpToNextLevel, 250)
        state.rewards = [RewardReceipt(xp: 200)]
        coreAssertEqual(state.xpToNextLevel, 50)
        state.rewards = [RewardReceipt(xp: 250)]
        coreAssertEqual(state.xpToNextLevel, 250)
    }

}

private let checks = CoreBehaviorChecks()
try checks.testCompletionAndReceiptAreIdempotentAcrossPersistence()
print("PASS testCompletionAndReceiptAreIdempotentAcrossPersistence")
try checks.testDateOnlyDeadlineIncludesWholeDayAndRejectsNextDay()
print("PASS testDateOnlyDeadlineIncludesWholeDayAndRejectsNextDay")
try checks.testExplicitDeadlineRewardBoundariesAndLevelTransition()
print("PASS testExplicitDeadlineRewardBoundariesAndLevelTransition")
try checks.testDailyOccurrencesDoNotDuplicateAndCompletedSnapshotsStayUnchanged()
print("PASS testDailyOccurrencesDoNotDuplicateAndCompletedSnapshotsStayUnchanged")
checks.testWeeklyAndShortMonthRecurrences()
print("PASS testWeeklyAndShortMonthRecurrences")
try checks.testOverdueOneOffRemainsVisibleAndCompletingTodayKeepsItsMustStatus()
print("PASS testOverdueOneOffRemainsVisibleAndCompletingTodayKeepsItsMustStatus")
try checks.testNoMustAndOptionalTasksNeverLockTheDay()
print("PASS testNoMustAndOptionalTasksNeverLockTheDay")
try checks.testFocusPauseAndProcessRestartExcludeIdleTime()
print("PASS testFocusPauseAndProcessRestartExcludeIdleTime")
try checks.testCompletingActiveTaskSavesFocusBeforeReceipt()
print("PASS testCompletingActiveTaskSavesFocusBeforeReceipt")
try checks.testCountdownNeedsGoalExtendsAndDoesNotAutoComplete()
print("PASS testCountdownNeedsGoalExtendsAndDoesNotAutoComplete")
try checks.testMidnightSplitUsesRunningIntervalsOnly()
print("PASS testMidnightSplitUsesRunningIntervalsOnly")
try checks.testCountdownBackgroundExpiryAndExtensionExcludeAbandonedTime()
print("PASS testCountdownBackgroundExpiryAndExtensionExcludeAbandonedTime")
try checks.testDSTDayBoundaryAndFixedTimeZone()
print("PASS testDSTDayBoundaryAndFixedTimeZone")
try checks.testStreakYesterdayGraceAndMedalsNeverRetract()
print("PASS testStreakYesterdayGraceAndMedalsNeverRetract")
try checks.testGrassIntensityIncludesSubMinuteAndUntimedCompletionAndNoFuture()
print("PASS testGrassIntensityIncludesSubMinuteAndUntimedCompletionAndNoFuture")
try checks.testDailyChecklistIsIndependentAndEditingPreservesProgress()
print("PASS testDailyChecklistIsIndependentAndEditingPreservesProgress")
try checks.testSessionMilestonesAndEmptyNotes()
print("PASS testSessionMilestonesAndEmptyNotes")

try checks.testMustFinaleOnlyForLastPendingMustAndNeverDuplicates()
print("PASS testMustFinaleOnlyForLastPendingMustAndNeverDuplicates")
try checks.testMustFinaleRespectsRolloverAndOverdueTasks()
print("PASS testMustFinaleRespectsRolloverAndOverdueTasks")
checks.testLevelFillHoldsFullBarBeforeCarryingXP()
print("PASS testLevelFillHoldsFullBarBeforeCarryingXP")

let persistenceCount = try runPersistenceChecks()
print("Passed 20 core behavior checks and \(persistenceCount) persistence checks.")
