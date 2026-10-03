import XCTest
import DopagakiCore
@testable import DopagakiPersistence

final class WidgetSnapshotRepositoryTests: XCTestCase {
    func testMissingGroupDoesNotInventAnEmptySuccessState() throws {
        let repository = WidgetSnapshotRepository(directory: nil)
        XCTAssertNil(try repository.load())
        XCTAssertFalse(try repository.save(WidgetProgressSnapshot(state: AppState(), at: Date())))
    }

    func testPublishingOnlyChangesAndRecoveringFromUnreadableProjection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = WidgetSnapshotRepository(directory: directory)
        let now = Date()
        var state = AppState()
        let initial = WidgetProgressSnapshot(state: state, at: now)
        XCTAssertNil(try repository.load())
        XCTAssertTrue(try repository.save(initial))
        XCTAssertFalse(try repository.save(initial))
        state.saveTask(TaskDefinition(title: "読む", createdAt: now, isMust: true), on: now)
        let changed = WidgetProgressSnapshot(state: state, at: now)
        XCTAssertTrue(try repository.save(changed))
        XCTAssertEqual(try repository.load(), changed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("state-v1.json").path))
        try Data("broken".utf8).write(to: directory.appendingPathComponent("widget-progress-v1.json"))
        XCTAssertThrowsError(try repository.load())
        XCTAssertTrue(try repository.save(changed))
        XCTAssertEqual(try repository.load(), changed)
    }
}
