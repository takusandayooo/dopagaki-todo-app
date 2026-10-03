import XCTest
@testable import DopagakiCore

final class WidgetProgressTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func state(_ zone: String = "Asia/Tokyo") -> AppState {
        AppState(settings: AppSettings(aggregationTimeZoneID: zone))
    }

    func testEmptyDayDoesNotCelebrateOrShowAFullRing() {
        let progress = WidgetDayProgress(state: state(), on: date("2026-10-03T10:00:00+09:00"))
        XCTAssertEqual(progress.mustRemaining, 0)
        XCTAssertEqual(progress.progress, 0)
        XCTAssertFalse(progress.mustComplete)
        XCTAssertEqual(progress.headline, "今日のマストなし")
    }

    func testCompletionSeparatesMustAndAllTasksAndUpdatesLevel() throws {
        let now = date("2026-10-03T10:00:00+09:00")
        var state = state()
        for title in ["ひとつ", "ふたつ", "みっつ"] {
            state.saveTask(TaskDefinition(title: title, createdAt: now, isMust: true), on: now)
        }
        state.saveTask(TaskDefinition(title: "任意", createdAt: now), on: now)
        let before = WidgetDayProgress(state: state, on: now)
        XCTAssertEqual(before.mustRemaining, 3)
        XCTAssertEqual(before.taskRemaining, 4)
        for occurrence in state.occurrences.filter(\.isMust) { state.complete(occurrenceID: occurrence.id, at: now) }
        let after = WidgetDayProgress(state: state, on: now)
        XCTAssertEqual(after.mustRemaining, 0)
        XCTAssertEqual(after.taskRemaining, 1)
        XCTAssertTrue(after.mustComplete)
        XCTAssertEqual(after.progress, 1)
        XCTAssertEqual(after.level, 2)
        XCTAssertEqual(after.xpToNextLevel, 200)
        XCTAssertEqual(after.reminderText, "マストは全達成！ほかのタスクはあと1個。")
    }

    func testTomorrowResetsRecurringMustButKeepsOverdueOneOffAndExcludesArchived() throws {
        let now = date("2026-10-03T23:59:00+09:00")
        let tomorrow = date("2026-10-04T00:00:00+09:00")
        var state = state()
        let daily = TaskDefinition(title: "毎日", recurrence: .init(frequency: .daily), createdAt: now, isMust: true)
        let overdue = TaskDefinition(title: "持ち越し", createdAt: now, isMust: true)
        let archived = TaskDefinition(title: "消したもの", createdAt: now, isMust: true)
        for task in [daily, overdue, archived] { state.saveTask(task, on: now) }
        state.archiveTask(id: archived.id)
        state.complete(occurrenceID: try XCTUnwrap(state.occurrences.first { $0.taskID == daily.id }?.id), at: now)
        let original = state
        let snapshot = WidgetProgressSnapshot(state: state, at: now)
        XCTAssertEqual(snapshot.progress(at: now)?.mustRemaining, 1)
        XCTAssertEqual(snapshot.progress(at: tomorrow)?.mustRemaining, 2)
        XCTAssertEqual(snapshot.progress(at: tomorrow)?.mustCompleted, 0)
        XCTAssertEqual(state, original, "Building the widget must not persist generated occurrences or rewards")
    }

    func testSnapshotExpiresInsteadOfShowingOldCountsForever() throws {
        let now = date("2026-10-03T10:00:00+09:00")
        let snapshot = WidgetProgressSnapshot(state: state(), at: now)
        XCTAssertEqual(snapshot.days.count, 8)
        let end = try XCTUnwrap(snapshot.days.last?.validUntil)
        XCTAssertNotNil(snapshot.progress(at: end.addingTimeInterval(-1)))
        XCTAssertNil(snapshot.progress(at: end))
        XCTAssertNil(snapshot.progress(at: snapshot.days[0].date.addingTimeInterval(-1)))
    }

    func testSnapshotUsesAggregationTimeZoneAcrossDaylightSaving() throws {
        let now = date("2026-11-01T00:30:00-07:00")
        let snapshot = WidgetProgressSnapshot(state: state("America/Los_Angeles"), at: now)
        let day = try XCTUnwrap(snapshot.progress(at: now))
        XCTAssertEqual(day.validUntil.timeIntervalSince(day.date), 25 * 3600)
        XCTAssertEqual(snapshot.progress(at: date("2026-11-01T23:30:00-08:00")), day)
        XCTAssertNotEqual(snapshot.progress(at: date("2026-11-02T00:00:00-08:00")), day)
    }

    func testSnapshotContainsNoTaskTitlesOrNotesAndRoundTrips() throws {
        let now = date("2026-10-03T10:00:00+09:00")
        var state = state()
        state.saveTask(TaskDefinition(title: "PRIVATE_TASK_TITLE", details: "PRIVATE_DETAIL", createdAt: now, isMust: true), on: now)
        state.addNote(occurrenceID: try XCTUnwrap(state.occurrences.first?.id), text: "PRIVATE_NOTE", photoNames: ["PRIVATE_PHOTO.jpg"], at: now)
        let snapshot = WidgetProgressSnapshot(state: state, at: now)
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE_"))
        XCTAssertEqual(try JSONDecoder().decode(WidgetProgressSnapshot.self, from: data), snapshot)
    }
}
