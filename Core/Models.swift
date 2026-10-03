import Foundation

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case low, normal, high
}

public enum RepeatFrequency: String, Codable, CaseIterable, Sendable {
    case none, daily, weekly, monthly
}

public struct RecurrenceRule: Codable, Equatable, Sendable {
    public var frequency: RepeatFrequency
    /// Calendar weekday numbers: Sunday = 1, Saturday = 7.
    public var weekdays: [Int]
    public var monthDay: Int
    public init(frequency: RepeatFrequency = .none, weekdays: [Int] = [], monthDay: Int = 1) {
        self.frequency = frequency
        self.weekdays = weekdays
        self.monthDay = monthDay
    }
}

public struct ChecklistItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool
    public init(id: UUID = UUID(), title: String = "", isDone: Bool = false) {
        self.id = id; self.title = title; self.isDone = isDone
    }
}

public struct TaskDefinition: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var details: String
    public var listName: String
    public var priority: TaskPriority
    public var recurrence: RecurrenceRule
    public var createdAt: Date
    public var deadline: Date?
    public var deadlineHasTime: Bool
    public var isMust: Bool
    public var targetMinutes: Int?
    public var labels: [String]
    public var checklist: [ChecklistItem]
    public var photoNames: [String]
    public var reminder: Date?
    public var archived: Bool
    public init(id: UUID = UUID(), title: String = "", details: String = "", listName: String = "暮らし", priority: TaskPriority = .normal, recurrence: RecurrenceRule = .init(), createdAt: Date = Date(), deadline: Date? = nil, deadlineHasTime: Bool = false, isMust: Bool = false, targetMinutes: Int? = nil, labels: [String] = [], checklist: [ChecklistItem] = [], photoNames: [String] = [], reminder: Date? = nil, archived: Bool = false) {
        self.id = id; self.title = title; self.details = details; self.listName = listName
        self.priority = priority; self.recurrence = recurrence; self.createdAt = createdAt
        self.deadline = deadline; self.deadlineHasTime = deadlineHasTime; self.isMust = isMust
        self.targetMinutes = targetMinutes; self.labels = labels; self.checklist = checklist
        self.photoNames = photoNames; self.reminder = reminder; self.archived = archived
    }
}

public struct TaskOccurrence: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var dayKey: String
    public var scheduledDate: Date
    public var title: String
    /// Resolved deadline; date-only deadlines are stored at the end of their day.
    public var deadline: Date?
    public var isMust: Bool
    public var completedAt: Date?
    public var checklist: [ChecklistItem]
    public var isCompleted: Bool { completedAt != nil }
    public init(id: UUID = UUID(), taskID: UUID = UUID(), dayKey: String = "", scheduledDate: Date = Date(), title: String = "", deadline: Date? = nil, isMust: Bool = false, completedAt: Date? = nil, checklist: [ChecklistItem] = []) {
        self.id = id; self.taskID = taskID; self.dayKey = dayKey; self.scheduledDate = scheduledDate
        self.title = title; self.deadline = deadline; self.isMust = isMust; self.completedAt = completedAt
        self.checklist = checklist
    }
}

public enum FocusMode: String, Codable, CaseIterable, Sendable {
    case stopwatch, countdown
}

public struct FocusSegment: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var duration: Double { max(0, end.timeIntervalSince(start)) }
    public init(start: Date = Date(), end: Date = Date()) { self.start = start; self.end = end }
}

public struct ActiveFocus: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var occurrenceID: UUID
    public var mode: FocusMode
    public var startedAt: Date
    public var accumulatedSeconds: Double
    public var runningSince: Date?
    public var targetSeconds: Double?
    /// Closed running intervals. Pauses are excluded, and intervals survive app restarts.
    public var segments: [FocusSegment]
    public var isPaused: Bool { runningSince == nil }
    public init(id: UUID = UUID(), occurrenceID: UUID = UUID(), mode: FocusMode = .stopwatch, startedAt: Date = Date(), accumulatedSeconds: Double = 0, runningSince: Date? = nil, targetSeconds: Double? = nil, segments: [FocusSegment] = []) {
        self.id = id; self.occurrenceID = occurrenceID; self.mode = mode; self.startedAt = startedAt
        self.accumulatedSeconds = accumulatedSeconds; self.runningSince = runningSince
        self.targetSeconds = targetSeconds; self.segments = segments
    }
    public func elapsed(at date: Date) -> Double {
        let raw = max(0, accumulatedSeconds) + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
        if mode == .countdown, let targetSeconds { return min(raw, max(0, targetSeconds)) }
        return raw
    }
}

public struct FocusSession: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var occurrenceID: UUID
    public var taskTitle: String
    public var startedAt: Date
    public var endedAt: Date
    public var segments: [FocusSegment]
    public var duration: Double { segments.reduce(0) { $0 + $1.duration } }
    public init(id: UUID = UUID(), occurrenceID: UUID = UUID(), taskTitle: String = "", startedAt: Date = Date(), endedAt: Date = Date(), segments: [FocusSegment] = []) {
        self.id = id; self.occurrenceID = occurrenceID; self.taskTitle = taskTitle
        self.startedAt = startedAt; self.endedAt = endedAt; self.segments = segments
    }
}

public struct ActivityNote: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var occurrenceID: UUID
    public var text: String
    public var photoNames: [String]
    public var createdAt: Date
    public init(id: UUID = UUID(), occurrenceID: UUID = UUID(), text: String = "", photoNames: [String] = [], createdAt: Date = Date()) {
        self.id = id; self.occurrenceID = occurrenceID; self.text = text; self.photoNames = photoNames; self.createdAt = createdAt
    }
}

public struct RewardReceipt: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var occurrenceID: UUID
    public var stars: Int
    public var xp: Int
    public var awardedAt: Date
    public init(id: UUID = UUID(), occurrenceID: UUID = UUID(), stars: Int = 3, xp: Int = 100, awardedAt: Date = Date()) {
        self.id = id; self.occurrenceID = occurrenceID; self.stars = stars; self.xp = xp; self.awardedAt = awardedAt
    }
}

public enum MedalKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case firstStep, weekStreak, monthStreak, tenHours, hundredHours, comeback
    public var id: Self { self }
    public var title: String {
        switch self {
        case .firstStep: return "最初の一歩"
        case .weekStreak: return "7日連続"
        case .monthStreak: return "30日連続"
        case .tenHours: return "10時間集中"
        case .hundredHours: return "100時間集中"
        case .comeback: return "再スタート"
        }
    }
    public var condition: String {
        switch self {
        case .firstStep: return "初めてタスクを完了する"
        case .weekStreak: return "7日連続で活動する"
        case .monthStreak: return "30日連続で活動する"
        case .tenHours: return "累計10時間、集中する"
        case .hundredHours: return "累計100時間、集中する"
        case .comeback: return "活動のない日を挟んで、再び取り組む"
        }
    }
    public var symbol: String {
        switch self {
        case .firstStep: return "checkmark"
        case .weekStreak: return "flame.fill"
        case .monthStreak: return "trophy.fill"
        case .tenHours: return "timer"
        case .hundredHours: return "crown.fill"
        case .comeback: return "leaf.fill"
        }
    }
}

public struct EarnedMedal: Identifiable, Codable, Equatable, Sendable {
    public var id: MedalKind
    public var earnedAt: Date
    public init(id: MedalKind = .firstStep, earnedAt: Date = Date()) { self.id = id; self.earnedAt = earnedAt }
}

public enum HapticLevel: String, Codable, CaseIterable, Sendable { case off, soft, standard, strong }

public struct AppSettings: Codable, Equatable, Sendable {
    public var haptics: HapticLevel
    public var soundEnabled: Bool
    public var reduceMotion: Bool
    public var remindersEnabled: Bool
    public var reminderHour: Int
    public var reminderDailyLimit: Int
    public var aggregationTimeZoneID: String
    public init(haptics: HapticLevel = .standard, soundEnabled: Bool = false, reduceMotion: Bool = false, remindersEnabled: Bool = false, reminderHour: Int = 19, reminderDailyLimit: Int = 2, aggregationTimeZoneID: String = TimeZone.current.identifier) {
        self.haptics = haptics; self.soundEnabled = soundEnabled; self.reduceMotion = reduceMotion
        self.remindersEnabled = remindersEnabled; self.reminderHour = reminderHour
        self.reminderDailyLimit = reminderDailyLimit; self.aggregationTimeZoneID = aggregationTimeZoneID
    }
}

public struct CompletionResult: Codable, Equatable, Sendable {
    public var receipt: RewardReceipt
    public var previousXP: Int
    public var totalXP: Int
    public var newMedals: [EarnedMedal]
    public var didLevelUp: Bool
    public var level: Int
    public var didCompleteTodaysMust: Bool
    public init(receipt: RewardReceipt = .init(), previousXP: Int = 0, totalXP: Int = 100, newMedals: [EarnedMedal] = [], didLevelUp: Bool = false, level: Int = 1, didCompleteTodaysMust: Bool = false) {
        self.receipt = receipt; self.previousXP = previousXP; self.totalXP = totalXP
        self.newMedals = newMedals; self.didLevelUp = didLevelUp; self.level = level
        self.didCompleteTodaysMust = didCompleteTodaysMust
    }
}

/// Presentation steps keep a full XP bar visible before starting the next level.
/// These are derived from the saved receipt and never award XP themselves.
public struct LevelFillStep: Equatable, Sendable {
    public let level: Int
    public let fromXP: Int
    public let toXP: Int
    public var reachesNextLevel: Bool { toXP == 250 }

    public static func steps(from previousXP: Int, to totalXP: Int) -> [LevelFillStep] {
        var cursor = max(0, previousXP)
        var result: [LevelFillStep] = []
        while cursor < totalXP {
            let level = cursor / 250 + 1
            let end = min(totalXP, level * 250)
            result.append(LevelFillStep(level: level, fromXP: cursor % 250, toXP: end - (level - 1) * 250))
            cursor = end
        }
        return result
    }
}

public struct DayActivity: Codable, Equatable, Sendable, Identifiable {
    public var dayKey: String
    public var date: Date
    public var seconds: Double
    public var completedCount: Int
    public var id: String { dayKey }
    public var isActive: Bool { seconds >= 1 || completedCount > 0 }
    public var intensity: Int {
        guard isActive else { return 0 }
        if seconds >= 3600 { return 4 }
        if seconds >= 1800 { return 3 }
        if seconds >= 900 { return 2 }
        return 1
    }
    public init(dayKey: String = "", date: Date = Date(), seconds: Double = 0, completedCount: Int = 0) {
        self.dayKey = dayKey; self.date = date; self.seconds = seconds; self.completedCount = completedCount
    }
}
