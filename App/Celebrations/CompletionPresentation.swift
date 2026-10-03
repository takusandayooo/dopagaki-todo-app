import DopagakiCore
import Foundation

public struct CompletionPresentation: Identifiable {
    public let id: UUID
    public let taskTitle: String
    public let stars: Int
    public let xp: Int
    public let previousXP: Int
    public let totalXP: Int
    public let level: Int
    public let didLevelUp: Bool
    public let newMedals: [EarnedMedal]
    public let occurrenceID: UUID
    public let didCompleteTodaysMust: Bool

    public init(id: UUID = UUID(), taskTitle: String, stars: Int, xp: Int, previousXP: Int, totalXP: Int, level: Int, didLevelUp: Bool, newMedals: [EarnedMedal], occurrenceID: UUID, didCompleteTodaysMust: Bool = false) {
        self.id = id
        self.taskTitle = taskTitle
        self.stars = max(0, min(3, stars))
        self.xp = max(0, xp)
        self.previousXP = max(0, previousXP)
        self.totalXP = max(0, totalXP)
        self.level = max(1, level)
        self.didLevelUp = didLevelUp
        self.newMedals = newMedals
        self.occurrenceID = occurrenceID
        self.didCompleteTodaysMust = didCompleteTodaysMust
    }
}
