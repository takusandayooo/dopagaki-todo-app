import Foundation

/// The persisted source of truth. Derived totals are calculated from immutable receipts and intervals.
public struct AppState: Codable, Equatable, Sendable {
    public var tasks: [TaskDefinition]
    public var listNames: [String]
    public var occurrences: [TaskOccurrence]
    public var sessions: [FocusSession]
    public var notes: [ActivityNote]
    public var rewards: [RewardReceipt]
    public var medals: [EarnedMedal]
    public var activeFocus: ActiveFocus?
    public var settings: AppSettings

    public init(tasks: [TaskDefinition] = [], listNames: [String] = ["英語", "仕事", "暮らし"], occurrences: [TaskOccurrence] = [], sessions: [FocusSession] = [], notes: [ActivityNote] = [], rewards: [RewardReceipt] = [], medals: [EarnedMedal] = [], activeFocus: ActiveFocus? = nil, settings: AppSettings = .init()) {
        self.tasks = tasks; self.listNames = listNames; self.occurrences = occurrences
        self.sessions = sessions; self.notes = notes; self.rewards = rewards
        self.medals = medals; self.activeFocus = activeFocus; self.settings = settings
    }

    public var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = Locale(identifier: "en_US_POSIX")
        result.timeZone = TimeZone(identifier: settings.aggregationTimeZoneID) ?? TimeZone(secondsFromGMT: 0)!
        result.firstWeekday = 1
        return result
    }

    public func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public var totalXP: Int { rewards.reduce(0) { $0 + max(0, $1.xp) } }
    public var level: Int { 1 + totalXP / 250 }
    public var levelProgress: Double { Double(totalXP % 250) / 250 }
    public var xpToNextLevel: Int { 250 - totalXP % 250 }
    public var totalSeconds: Double { sessions.reduce(0) { $0 + $1.duration } }

    public mutating func ensureOccurrences(on date: Date) {
        let day = calendar.startOfDay(for: date)
        for definition in tasks where !definition.archived {
            guard calendar.startOfDay(for: definition.createdAt) <= day else { continue }
            let occurrenceDay: Date
            if definition.recurrence.frequency == .none {
                // A one-off task has exactly one execution, including when it becomes overdue.
                occurrenceDay = calendar.startOfDay(for: definition.createdAt)
                guard !occurrences.contains(where: { $0.taskID == definition.id }) else { continue }
            } else {
                guard isScheduled(definition, on: day) else { continue }
                occurrenceDay = day
                let key = dayKey(for: day)
                guard !occurrences.contains(where: { $0.taskID == definition.id && $0.dayKey == key }) else { continue }
            }
            let checklist = definition.checklist.map { item in
                ChecklistItem(id: item.id, title: item.title, isDone: definition.recurrence.frequency == .none && item.isDone)
            }
            occurrences.append(TaskOccurrence(taskID: definition.id, dayKey: dayKey(for: occurrenceDay), scheduledDate: occurrenceDay, title: definition.title, deadline: resolvedDeadline(for: definition, on: occurrenceDay), isMust: definition.isMust, checklist: checklist))
        }
    }

    public mutating func saveTask(_ task: TaskDefinition, on date: Date) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task }
        else { tasks.append(task) }
        if !task.listName.isEmpty && !listNames.contains(task.listName) { listNames.append(task.listName) }
        let today = calendar.startOfDay(for: date)
        for index in occurrences.indices where occurrences[index].taskID == task.id && !occurrences[index].isCompleted {
            // Past repeating executions stay as snapshots. Pending one-offs remain editable.
            guard task.recurrence.frequency == .none || occurrences[index].scheduledDate >= today else { continue }
            occurrences[index].title = task.title
            occurrences[index].deadline = resolvedDeadline(for: task, on: occurrences[index].scheduledDate)
            occurrences[index].isMust = task.isMust
            let existing = occurrences[index].checklist
            occurrences[index].checklist = task.checklist.map { item in
                ChecklistItem(id: item.id, title: item.title, isDone: existing.first(where: { $0.id == item.id })?.isDone ?? (task.recurrence.frequency == .none && item.isDone))
            }
        }
        ensureOccurrences(on: date)
    }

    public mutating func archiveTask(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].archived = true
    }

    public mutating func setMust(occurrenceID: UUID, value: Bool) {
        guard let index = occurrences.firstIndex(where: { $0.id == occurrenceID }) else { return }
        occurrences[index].isMust = value
    }

    public mutating func setChecklistItem(occurrenceID: UUID, itemID: UUID, isDone: Bool) {
        guard let occurrence = occurrences.firstIndex(where: { $0.id == occurrenceID }),
              !occurrences[occurrence].isCompleted,
              let item = occurrences[occurrence].checklist.firstIndex(where: { $0.id == itemID }) else { return }
        occurrences[occurrence].checklist[item].isDone = isDone
    }

    public func occurrences(on date: Date) -> [TaskOccurrence] {
        let key = dayKey(for: date)
        let day = calendar.startOfDay(for: date)
        return occurrences.filter { occurrence in
            guard let definition = tasks.first(where: { $0.id == occurrence.taskID }), !definition.archived else { return false }
            if occurrence.dayKey == key { return true }
            if let completed = occurrence.completedAt, dayKey(for: completed) == key { return true }
            return definition.recurrence.frequency == .none && !occurrence.isCompleted && occurrence.scheduledDate < day
        }.sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            if $0.isMust != $1.isMust { return $0.isMust }
            return $0.scheduledDate < $1.scheduledDate
        }
    }

    public func todaysMustComplete(on date: Date) -> Bool {
        occurrences(on: date).filter(\.isMust).allSatisfy(\.isCompleted)
    }

    /// Completion and its unique receipt are committed together before any animation is played.
    @discardableResult
    public mutating func complete(occurrenceID: UUID, at date: Date) -> CompletionResult? {
        guard let index = occurrences.firstIndex(where: { $0.id == occurrenceID }),
              !occurrences[index].isCompleted,
              !rewards.contains(where: { $0.occurrenceID == occurrenceID }) else { return nil }
        ensureOccurrences(on: date)
        let previousXP = totalXP
        let oldMedals = Set(medals.map(\.id))
        // Evaluate the current day's pending musts before completion. Historical
        // repeating tasks and days with no musts must not trigger the finale.
        let pendingMusts = occurrences(on: date).filter { $0.isMust && !$0.isCompleted }
        let didCompleteTodaysMust = pendingMusts.count == 1 && pendingMusts.first?.id == occurrenceID
        if activeFocus?.occurrenceID == occurrenceID { _ = finishFocus(at: date) }
        let deadline = occurrences[index].deadline
        let lateness = deadline.map { date.timeIntervalSince($0) } ?? 0
        let stars: Int
        let xp: Int
        if lateness <= 0 { stars = 3; xp = 100 }
        else if lateness <= 24 * 60 * 60 { stars = 2; xp = 70 }
        else { stars = 1; xp = 50 }
        let receipt = RewardReceipt(occurrenceID: occurrenceID, stars: stars, xp: xp, awardedAt: date)
        occurrences[index].completedAt = date
        rewards.append(receipt)
        refreshMedals(at: date)
        return CompletionResult(receipt: receipt, previousXP: previousXP, totalXP: totalXP, newMedals: medals.filter { !oldMedals.contains($0.id) }, didLevelUp: level > 1 + previousXP / 250, level: level, didCompleteTodaysMust: didCompleteTodaysMust)
    }

    @discardableResult
    public mutating func startFocus(occurrenceID: UUID, mode: FocusMode, targetMinutes: Int? = nil, at date: Date) -> Bool {
        guard activeFocus == nil,
              let occurrence = occurrences.first(where: { $0.id == occurrenceID }), !occurrence.isCompleted,
              tasks.contains(where: { $0.id == occurrence.taskID && !$0.archived }) else { return false }
        let target = targetMinutes.flatMap { $0 > 0 ? Double($0) * 60 : nil }
        // A countdown needs a duration; a stopwatch may have an optional goal.
        guard mode != .countdown || target != nil else { return false }
        activeFocus = ActiveFocus(occurrenceID: occurrenceID, mode: mode, startedAt: date, runningSince: date, targetSeconds: target)
        return true
    }

    public mutating func pauseFocus(at date: Date) {
        guard var focus = activeFocus, let start = focus.runningSince else { return }
        var end = max(start, date)
        if focus.mode == .countdown, let target = focus.targetSeconds {
            let deadline = start.addingTimeInterval(max(0, target - focus.accumulatedSeconds))
            end = min(end, deadline)
        }
        let segment = FocusSegment(start: start, end: end)
        focus.segments.append(segment)
        focus.accumulatedSeconds += segment.duration
        focus.runningSince = nil
        activeFocus = focus
    }

    public mutating func resumeFocus(at date: Date) {
        guard var focus = activeFocus, focus.isPaused else { return }
        // A backwards clock change must not overlap a previously saved interval.
        focus.runningSince = max(date, focus.segments.last?.end ?? focus.startedAt)
        activeFocus = focus
    }

    public mutating func extendFocus(minutes: Int, at date: Date = Date()) {
        guard minutes > 0, let current = activeFocus else { return }
        if current.mode == .countdown, let target = current.targetSeconds,
           current.runningSince != nil, current.elapsed(at: date) >= target {
            // Close the original countdown before raising its limit. Time spent away after
            // expiry must never become activity just because the user adds more minutes.
            pauseFocus(at: date)
        }
        guard var focus = activeFocus else { return }
        focus.targetSeconds = max(0, focus.targetSeconds ?? 0) + Double(minutes) * 60
        activeFocus = focus
    }

    @discardableResult
    public mutating func finishFocus(at date: Date) -> FocusSession? {
        guard activeFocus != nil else { return nil }
        pauseFocus(at: date)
        guard let focus = activeFocus else { return nil }
        let title = occurrences.first(where: { $0.id == focus.occurrenceID })?.title ?? "集中"
        let end = max(date, focus.segments.last?.end ?? focus.startedAt)
        let session = FocusSession(id: focus.id, occurrenceID: focus.occurrenceID, taskTitle: title, startedAt: focus.startedAt, endedAt: end, segments: focus.segments)
        sessions.append(session)
        activeFocus = nil
        refreshMedals(at: date)
        return session
    }

    public mutating func addNote(occurrenceID: UUID, text: String, photoNames: [String] = [], at date: Date) {
        guard occurrences.contains(where: { $0.id == occurrenceID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !photoNames.isEmpty else { return }
        notes.append(ActivityNote(occurrenceID: occurrenceID, text: trimmed, photoNames: photoNames, createdAt: date))
    }

    public func activity(on date: Date) -> DayActivity {
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        let seconds = sessions.flatMap(\.segments).reduce(0.0) { sum, interval in
            sum + max(0, min(interval.end, next).timeIntervalSince(max(interval.start, day)))
        }
        let completed = occurrences.filter { occurrence in
            guard let completion = occurrence.completedAt else { return false }
            return completion >= day && completion < next
        }.count
        return DayActivity(dayKey: dayKey(for: day), date: day, seconds: seconds, completedCount: completed)
    }

    /// Sunday-aligned columns, including the current week up to `ending` and never future cells.
    public func activityDays(ending date: Date, weeks: Int = 13) -> [DayActivity] {
        guard weeks > 0 else { return [] }
        let end = calendar.startOfDay(for: date)
        let weekdayOffset = calendar.component(.weekday, from: end) - 1
        let currentSunday = calendar.date(byAdding: .day, value: -weekdayOffset, to: end)!
        let start = calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: currentSunday)!
        var day = start
        var result: [DayActivity] = []
        while day <= end {
            result.append(activity(on: day))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    public func currentStreak(at date: Date) -> Int {
        let active = Set(activeDays())
        var day = calendar.startOfDay(for: date)
        if !active.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while active.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    public func longestStreak() -> Int {
        let days = activeDays()
        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day { run += 1 }
            else { run = 1 }
            best = max(best, run)
            previous = day
        }
        return best
    }

    private func isScheduled(_ definition: TaskDefinition, on day: Date) -> Bool {
        guard calendar.startOfDay(for: definition.createdAt) <= day else { return false }
        switch definition.recurrence.frequency {
        case .none, .daily: return true
        case .weekly:
            let weekdays = definition.recurrence.weekdays.filter { (1...7).contains($0) }
            let expected = weekdays.isEmpty ? [calendar.component(.weekday, from: definition.createdAt)] : weekdays
            return expected.contains(calendar.component(.weekday, from: day))
        case .monthly:
            let requested = min(31, max(1, definition.recurrence.monthDay))
            let last = calendar.range(of: .day, in: .month, for: day)!.count
            return calendar.component(.day, from: day) == min(requested, last)
        }
    }

    private func resolvedDeadline(for definition: TaskDefinition, on occurrenceDay: Date) -> Date? {
        guard let deadline = definition.deadline else { return nil }
        var result = deadline
        if definition.recurrence.frequency != .none {
            let time = calendar.dateComponents([.hour, .minute, .second], from: deadline)
            result = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: occurrenceDay) ?? occurrenceDay
        }
        if !definition.deadlineHasTime {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: result))!
            result = nextDay.addingTimeInterval(-0.001)
        }
        return result
    }

    /// Dates come from actual running intervals and completion times, not scheduled task dates.
    private func activeDays() -> [Date] {
        var candidates = Set<Date>()
        for interval in sessions.flatMap(\.segments) where interval.duration > 0 {
            var day = calendar.startOfDay(for: interval.start)
            while day < interval.end {
                candidates.insert(day)
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
        for completion in occurrences.compactMap(\.completedAt) {
            candidates.insert(calendar.startOfDay(for: completion))
        }
        return candidates.filter { activity(on: $0).isActive }.sorted()
    }

    private mutating func refreshMedals(at date: Date) {
        let longest = longestStreak()
        let days = activeDays()
        let comeback = zip(days, days.dropFirst()).contains { previous, next in
            (calendar.dateComponents([.day], from: previous, to: next).day ?? 0) >= 2
        }
        let eligible: [(MedalKind, Bool)] = [
            (.firstStep, occurrences.contains(where: \.isCompleted)),
            (.weekStreak, longest >= 7), (.monthStreak, longest >= 30),
            (.tenHours, totalSeconds >= 10 * 3600), (.hundredHours, totalSeconds >= 100 * 3600),
            (.comeback, comeback)
        ]
        for (kind, isEligible) in eligible where isEligible && !medals.contains(where: { $0.id == kind }) {
            medals.append(EarnedMedal(id: kind, earnedAt: date))
        }
    }
}
