import Foundation

nonisolated struct FinancialInputs: Equatable, Sendable {
    let savingsMinor: Int64
    let incomeMinor: Int64
    let expensesMinor: Int64
    let targetMinor: Int64
    let evaluationDate: Date
    let targetDate: Date
}

nonisolated enum GoalFundingStatus: Equatable, Sendable {
    case fundedNow
    case onTrack(completionDate: Date, deadlineBalanceMinor: Int64, monthsToDeadline: Int)
    case atRisk(completionDate: Date?, deadlineBalanceMinor: Int64, monthsToDeadline: Int)
    case noContributionBeforeDeadline
    case pastDeadline
    case nonpositiveCapacity
    case invalidInputs
    case overflow
    case completionBeyondLimit
}

nonisolated struct FinancialCalculationResult: Equatable, Sendable {
    let monthlyCapacityMinor: Int64
    let remainingMinor: Int64
    let progress: Double
    let monthlyRequiredMinor: Int64
    let deadlineBalanceMinor: Int64
    let monthsToDeadline: Int
    let status: GoalFundingStatus
}
