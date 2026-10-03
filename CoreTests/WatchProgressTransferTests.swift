import XCTest
@testable import DopagakiCore

final class WatchProgressTransferTests: XCTestCase {
    private func payload() throws -> Data {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = AppState()
        state.saveTask(TaskDefinition(title: "PRIVATE_TASK_TITLE", details: "PRIVATE_DETAIL", createdAt: now, isMust: true), on: now)
        return try JSONEncoder().encode(WatchProgressTransfer(snapshot: WidgetProgressSnapshot(state: state, at: now), updatedAt: now))
    }

    func testRoundTripContainsOnlyAggregateProgress() throws {
        let data = try payload()
        let decoded = try WatchProgressTransfer.decode(data)
        XCTAssertEqual(decoded.snapshot.days.count, 8)
        XCTAssertEqual(decoded.snapshot.days.first?.mustRemaining, 1)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE_"))
        XCTAssertEqual(try WatchProgressTransfer.decode(JSONEncoder().encode(decoded)), decoded)
    }

    func testRejectsUnknownVersionsAndOversizedMessages() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload()) as? [String: Any])
        object["schemaVersion"] = 2
        XCTAssertThrowsError(try WatchProgressTransfer.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try WatchProgressTransfer.decode(Data(repeating: 32, count: 65_537)))
    }

    func testRejectsInvalidCountsAndDiscontinuousDates() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: payload()) as? [String: Any])
        for field in ["mustCompleted", "taskRemaining", "level", "validUntil"] {
            var object = original
            var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
            var days = try XCTUnwrap(snapshot["days"] as? [[String: Any]])
            days[0][field] = -1
            snapshot["days"] = days
            object["snapshot"] = snapshot
            XCTAssertThrowsError(try WatchProgressTransfer.decode(JSONSerialization.data(withJSONObject: object)), field)
        }
        var object = original
        var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        var days = try XCTUnwrap(snapshot["days"] as? [[String: Any]])
        days.remove(at: 1)
        snapshot["days"] = days; object["snapshot"] = snapshot
        XCTAssertThrowsError(try WatchProgressTransfer.decode(JSONSerialization.data(withJSONObject: object)))
    }
}
