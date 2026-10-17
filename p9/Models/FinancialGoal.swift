import Foundation
import SwiftData

//stores a savings Goal
// - goal name
// - target amount
// - target date (to achieve goal by)
// - description (optional)


@Model
final class FinancialGoal {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var name: String
    var targetAmountMinor: Int64
    var targetDate: Date
    var goalDescription: String?
    var priorityRawValue: Int = 1

    var priority: GoalPriority {
        get { GoalPriority(rawValue: priorityRawValue) ?? .medium }
        set { priorityRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String,
        targetAmountMinor: Int64,
        targetDate: Date,
        goalDescription: String? = nil,
        priority: GoalPriority = .medium
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.targetAmountMinor = targetAmountMinor
        // Store goal deadlines as a calendar day, not an exact user-time timestamp.
        self.targetDate = FinancialCalendar.utcNoon(for: targetDate)
        self.goalDescription = goalDescription
        self.priority = priority
    }
}
