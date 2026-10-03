import XCTest
import DopagakiCore
@testable import DopagakiPersistence

final class WatchProgressRepositoryTests: XCTestCase {
    private func transfer(at date: Date) -> WatchProgressTransfer {
        WatchProgressTransfer(snapshot: WidgetProgressSnapshot(state: AppState(), at: date), updatedAt: date)
    }

    func testOutOfOrderAndDuplicateDeliveriesDoNotOverwriteLatest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = WatchProgressRepository(directory: directory)
        let latest = transfer(at: Date())
        let data = try JSONEncoder().encode(latest)
        XCTAssertNil(try repository.load())
        XCTAssertTrue(try repository.receive(data))
        XCTAssertFalse(try repository.receive(data))
        XCTAssertFalse(try repository.receive(JSONEncoder().encode(transfer(at: latest.updatedAt.addingTimeInterval(-60)))))
        XCTAssertEqual(try repository.load(), latest)
        XCTAssertThrowsError(try repository.receive(Data("invalid".utf8)))
        XCTAssertEqual(try repository.load(), latest)
        let newer = transfer(at: latest.updatedAt.addingTimeInterval(60))
        XCTAssertTrue(try repository.receive(JSONEncoder().encode(newer)))
        XCTAssertEqual(try repository.load(), newer)
    }

    func testUnavailableGroupDoesNotPretendToSave() throws {
        let repository = WatchProgressRepository(directory: nil)
        XCTAssertNil(try repository.load())
        XCTAssertThrowsError(try repository.receive(JSONEncoder().encode(transfer(at: Date()))))
    }
}
