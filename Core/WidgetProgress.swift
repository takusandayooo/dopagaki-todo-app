import Foundation

/// A title-free, read-only projection. Widgets never write task or reward data.
public struct WidgetDayProgress: Codable, Equatable, Sendable {
    public let date: Date
    public let validUntil: Date
    public let mustTotal: Int
    public let mustCompleted: Int
    public let taskRemaining: Int
    public let level: Int
    public let xpToNextLevel: Int

    public var mustRemaining: Int { max(0, mustTotal - mustCompleted) }
    public var mustComplete: Bool { mustTotal > 0 && mustRemaining == 0 }
    public var progress: Double { mustTotal == 0 ? 0 : Double(mustCompleted) / Double(mustTotal) }
    public var headline: String {
        if mustTotal == 0 { return "今日のマストなし" }
        if mustComplete { return "マスト全達成！" }
        return "マストあと\(mustRemaining)個"
    }
    public var reminderText: String {
        if mustRemaining > 0 { return "今日のマストはあと\(mustRemaining)個。ひとつ進めよう。" }
        if mustComplete { return "マストは全達成！ほかのタスクはあと\(taskRemaining)個。" }
        return "今日のタスクはあと\(taskRemaining)個。ひとつ進めよう。"
    }

    public init(state: AppState, on date: Date) {
        var snapshot = state
        snapshot.ensureOccurrences(on: date)
        let today = snapshot.occurrences(on: date)
        let must = today.filter(\.isMust)
        self.date = snapshot.calendar.startOfDay(for: date)
        validUntil = snapshot.calendar.date(byAdding: .day, value: 1, to: self.date)!
        mustTotal = must.count
        mustCompleted = must.filter(\.isCompleted).count
        taskRemaining = today.filter { !$0.isCompleted }.count
        level = snapshot.level
        xpToNextLevel = snapshot.xpToNextLevel
    }
}

public struct WidgetProgressSnapshot: Codable, Equatable, Sendable {
    public let days: [WidgetDayProgress]
    public init(state: AppState, at now: Date) {
        // Calendar dates (not 86,400 seconds) preserve day boundaries across DST.
        let start = state.calendar.startOfDay(for: now)
        days = (0..<8).compactMap { offset in
            guard let date = state.calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return WidgetDayProgress(state: state, on: date)
        }
    }
    public func progress(at date: Date) -> WidgetDayProgress? {
        days.first { $0.date <= date && date < $0.validUntil }
    }
}
