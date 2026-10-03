import Foundation

/// Versioned, title-free message for the paired Watch. No task mutation is supported.
public struct WatchProgressTransfer: Codable, Equatable, Sendable {
    public static let messageKey = "dopagaki.progress"
    public static let requestKey = "dopagaki.requestProgress"
    public let schemaVersion: Int
    public let updatedAt: Date
    public let snapshot: WidgetProgressSnapshot

    public init(snapshot: WidgetProgressSnapshot, updatedAt: Date) {
        schemaVersion = 1
        self.updatedAt = updatedAt
        self.snapshot = snapshot
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 65_536 else { throw TransferError.invalidPayload }
        let transfer = try JSONDecoder().decode(Self.self, from: data)
        guard transfer.schemaVersion == 1,
              transfer.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              (1...8).contains(transfer.snapshot.days.count) else { throw TransferError.invalidPayload }
        var previousEnd: Date?
        for day in transfer.snapshot.days {
            guard day.date.timeIntervalSinceReferenceDate.isFinite,
                  day.validUntil > day.date,
                  day.validUntil.timeIntervalSince(day.date) <= 26 * 3600,
                  previousEnd == nil || previousEnd == day.date,
                  day.mustTotal >= 0, day.mustCompleted >= 0, day.mustCompleted <= day.mustTotal,
                  day.taskRemaining >= day.mustRemaining,
                  day.level >= 1, (1...250).contains(day.xpToNextLevel) else { throw TransferError.invalidPayload }
            previousEnd = day.validUntil
        }
        return transfer
    }

    public enum TransferError: Error { case invalidPayload }
}
