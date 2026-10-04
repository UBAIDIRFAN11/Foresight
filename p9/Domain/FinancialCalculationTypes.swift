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
    let completionProjection: GoalCompletionProjection
}

nonisolated enum GoalCompletionProjection: Equatable, Sendable {
    case completedNow
    case projected(months: Int, date: Date)
    case noPositiveSavingsCapacity
    case beyondLimit
}

nonisolated struct PurchaseImpactInputs: Equatable, Sendable {
    let financialInputs: FinancialInputs
    let purchaseAmountMinor: Int64
}

nonisolated enum PurchaseImpactError: LocalizedError, Equatable, Sendable {
    case invalidFinancialInputs
    case invalidPurchaseAmount
    case insufficientSavings
    case arithmeticOverflow

    var errorDescription: String? {
        switch self {
        case .invalidFinancialInputs: "Check your profile and goal amounts before calculating."
        case .invalidPurchaseAmount: "Purchase amount must be greater than zero."
        case .insufficientSavings: "This purchase is higher than your current savings."
        case .arithmeticOverflow: "The numbers are too large to calculate safely."
        }
    }
}

nonisolated enum PurchaseImpactUnavailableReason: String, Equatable, Sendable {
    case currentPlanAlreadyMissesDeadline
    case pastDeadline
    case noDepositsBeforeDeadline
    case noPositiveSavingsCapacity
    case projectionBeyondLimit
    case arithmeticOverflow
    case notNeeded
}

nonisolated enum PurchaseImpactMetric: Equatable, Sendable {
    case amount(Int64)
    case months(Int)
    case unavailable(PurchaseImpactUnavailableReason)

    var amountMinor: Int64? {
        if case .amount(let value) = self { value } else { nil }
    }

    var monthCount: Int? {
        if case .months(let value) = self { value } else { nil }
    }
}

nonisolated struct PurchaseImpactResult: Equatable, Sendable {
    let baseline: FinancialCalculationResult
    let afterPurchase: FinancialCalculationResult
    let remainingSavingsMinor: Int64
    let deadlineBalanceBeforeMinor: Int64
    let deadlineBalanceAfterMinor: Int64
    let purchaseDelay: PurchaseImpactMetric
    let extraMonthlySavings: PurchaseImpactMetric
    let maximumPurchasePreservingDeadline: PurchaseImpactMetric
}
