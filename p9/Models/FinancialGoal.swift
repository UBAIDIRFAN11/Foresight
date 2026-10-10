import Foundation
import SwiftData

//stores a savings Goal
// - goal name
// - target amount
// - target date (to achieve goal by)
// - priority
// - description (optional)


@Model
final class FinancialGoal {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var name: String
    var targetAmountMinor: Int64
    var targetDate: Date
    var priorityRawValue: Int
    var goalDescription: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String,
        targetAmountMinor: Int64,
        targetDate: Date,
        priority: GoalPriority = .medium,
        goalDescription: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.targetAmountMinor = targetAmountMinor
        // Store goal deadlines as a calendar day, not an exact user-time timestamp.
        self.targetDate = FinancialCalendar.utcNoon(for: targetDate)
        self.priorityRawValue = priority.rawValue
        self.goalDescription = goalDescription
    }

    var priority: GoalPriority {
        get { GoalPriority(rawValue: priorityRawValue) ?? .medium }
        set { priorityRawValue = newValue.rawValue }
    }
}

enum GoalPriority: Int, CaseIterable, Identifiable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}
