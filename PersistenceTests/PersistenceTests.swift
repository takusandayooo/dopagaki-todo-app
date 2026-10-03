import XCTest
import DopagakiCore
@testable import DopagakiPersistence

final class PersistenceTests: XCTestCase {
    private func isolatedDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dopagaki-tests-\(UUID())", isDirectory: true)
    }

    func testNewInstallationHasNoInventedHistory() throws {
        let folder = isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = try StateRepository(directory: folder).load()
        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertTrue(state.rewards.isEmpty)
        XCTAssertTrue(state.medals.isEmpty)
    }

    func testPersistedRunningSessionAndRewardSurviveRelaunch() throws {
        let folder = isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        var state = AppState(settings: .init(aggregationTimeZoneID: "Asia/Tokyo"))
        state.saveTask(TaskDefinition(title: "英語", createdAt: now), on: now)
        let completedID = try XCTUnwrap(state.occurrences.first?.id)
        _ = state.complete(occurrenceID: completedID, at: now)
        state.saveTask(TaskDefinition(title: "読書", createdAt: now), on: now)
        let runningID = try XCTUnwrap(state.occurrences.first { $0.id != completedID }?.id)
        XCTAssertTrue(state.startFocus(occurrenceID: runningID, mode: .stopwatch, at: now))
        let repository = StateRepository(directory: folder)
        try repository.save(state)
        var restored = try StateRepository(directory: folder).load()
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.activeFocus?.elapsed(at: now.addingTimeInterval(60)), 60)
        XCTAssertNil(restored.complete(occurrenceID: completedID, at: now.addingTimeInterval(60)))
        XCTAssertEqual(restored.totalXP, 100)
    }

    func testCorruptedSnapshotCanBeBackedUpWithoutDestroyingIt() throws {
        let folder = isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = StateRepository(directory: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let damaged = Data("unreadable original snapshot".utf8)
        try damaged.write(to: repository.stateURL)
        XCTAssertThrowsError(try repository.load())
        let backup = try repository.preserveUnreadableSnapshot()
        XCTAssertEqual(try Data(contentsOf: backup), damaged)
        XCTAssertEqual(try Data(contentsOf: repository.stateURL), damaged)
        try repository.save(AppState())
        XCTAssertEqual(try Data(contentsOf: backup), damaged)
        XCTAssertTrue(try repository.load().tasks.isEmpty)
    }

    func testPhotoStorageCannotEscapeItsDirectory() throws {
        let folder = isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = StateRepository(directory: folder)
        let data = Data([1, 2, 3])
        let name = try repository.savePhoto(data)
        let url = try XCTUnwrap(repository.photoURL(name))
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertNil(repository.photoURL("../state-v1.json"))
        XCTAssertNil(repository.photoURL("/etc/hosts"))
    }

    func testFailedSaveDoesNotReplaceExistingBytes() throws {
        let folder = isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blockedFolder = folder.appendingPathComponent("blocked")
        let original = Data("keep me".utf8)
        try original.write(to: blockedFolder)
        let repository = StateRepository(directory: blockedFolder)
        XCTAssertThrowsError(try repository.save(AppState()))
        XCTAssertEqual(try Data(contentsOf: blockedFolder), original)
    }
}
