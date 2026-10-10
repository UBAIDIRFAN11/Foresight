import Foundation
import SwiftData

@Model
final class SavedDecision {
    //saved decisions are flat snapshots. They intentionally copy goal/profile
    // values so History remains readable after later edits or deletion.
    @Attribute(.unique) var evaluationID: UUID
    var savedAt: Date
    var purchaseName: String
    var purchaseAmountMinor: Int64
    var currencyCode: String
    var goalID: UUID
    var goalName: String
    var goalTargetMinor: Int64
    var goalTargetDate: Date
    var originalSavingsMinor: Int64
    var originalIncomeMinor: Int64
    var originalExpensesMinor: Int64
    var evaluationDate: Date
    var remainingSavingsMinor: Int64
    var baselineDeadlineBalanceMinor: Int64
    var afterDeadlineBalanceMinor: Int64
    var baselineCompletionKind: String
    var baselineCompletionMonths: Int
    var baselineCompletionDate: Date?
    var afterCompletionKind: String
    var afterCompletionMonths: Int
    var afterCompletionDate: Date?
    var delayKind: String
    var delayMonths: Int
    var extraMonthlyKind: String
    var extraMonthlyMinor: Int64
    var maximumPurchaseKind: String
    var maximumPurchaseMinor: Int64
    var baselineStatus: String
    var afterStatus: String

    init(evaluation: PurchaseImpactEvaluation, savedAt: Date = Date()) {
        // Copy every value the result screen needs at save time.
        self.evaluationID = evaluation.id
        self.savedAt = savedAt
        self.purchaseName = evaluation.purchaseName
        self.purchaseAmountMinor = evaluation.purchaseAmountMinor
        self.currencyCode = evaluation.currencyCode
        self.goalID = evaluation.goalID
        self.goalName = evaluation.goalName
        self.goalTargetMinor = evaluation.goalTargetMinor
        self.goalTargetDate = evaluation.goalTargetDate
        self.originalSavingsMinor = evaluation.originalSavingsMinor
        self.originalIncomeMinor = evaluation.originalIncomeMinor
        self.originalExpensesMinor = evaluation.originalExpensesMinor
        self.evaluationDate = evaluation.evaluationDate
        self.remainingSavingsMinor = evaluation.result.remainingSavingsMinor
        self.baselineDeadlineBalanceMinor = evaluation.result.deadlineBalanceBeforeMinor
        self.afterDeadlineBalanceMinor = evaluation.result.deadlineBalanceAfterMinor
        self.baselineCompletionKind = evaluation.result.baseline.completionProjection.storageKind
        self.baselineCompletionMonths = evaluation.result.baseline.completionProjection.storageMonths
        self.baselineCompletionDate = evaluation.result.baseline.completionProjection.storageDate
        self.afterCompletionKind = evaluation.result.afterPurchase.completionProjection.storageKind
        self.afterCompletionMonths = evaluation.result.afterPurchase.completionProjection.storageMonths
        self.afterCompletionDate = evaluation.result.afterPurchase.completionProjection.storageDate
        self.delayKind = evaluation.result.purchaseDelay.storageKind
        self.delayMonths = evaluation.result.purchaseDelay.storageMonths
        self.extraMonthlyKind = evaluation.result.extraMonthlySavings.storageKind
        self.extraMonthlyMinor = evaluation.result.extraMonthlySavings.storageAmount
        self.maximumPurchaseKind = evaluation.result.maximumPurchasePreservingDeadline.storageKind
        self.maximumPurchaseMinor = evaluation.result.maximumPurchasePreservingDeadline.storageAmount
        self.baselineStatus = evaluation.result.baseline.status.summaryTitle
        self.afterStatus = evaluation.result.afterPurchase.status.summaryTitle
    }
}

// In-memory version of a purchase impact. Simulator creates this first;
// saving converts it into a SwiftData SavedDecision.
struct PurchaseImpactEvaluation: Identifiable, Equatable {
    let id: UUID
    let purchaseName: String
    let purchaseAmountMinor: Int64
    let currencyCode: String
    let goalID: UUID
    let goalName: String
    let goalTargetMinor: Int64
    let goalTargetDate: Date
    let originalSavingsMinor: Int64
    let originalIncomeMinor: Int64
    let originalExpensesMinor: Int64
    let evaluationDate: Date
    let result: PurchaseImpactResult
}

extension SavedDecision {
    var evaluationSnapshot: PurchaseImpactEvaluation {
        // Rebuild a display-ready result from stored snapshot fields.
        // This does not recalculate using the current profile or current goal.
        let baseline = FinancialCalculationResult(
            monthlyCapacityMinor: originalIncomeMinor - originalExpensesMinor,
            remainingMinor: max(goalTargetMinor - originalSavingsMinor, 0),
            progress: min(Double(originalSavingsMinor) / Double(goalTargetMinor), 1),
            monthlyRequiredMinor: 0,
            deadlineBalanceMinor: baselineDeadlineBalanceMinor,
            monthsToDeadline: FinancialCalendar.monthsWithDeposits(from: evaluationDate, through: goalTargetDate),
            status: .fundedNow,
            completionProjection: GoalCompletionProjection(kind: baselineCompletionKind, months: baselineCompletionMonths, date: baselineCompletionDate)
        )
        let after = FinancialCalculationResult(
            monthlyCapacityMinor: originalIncomeMinor - originalExpensesMinor,
            remainingMinor: max(goalTargetMinor - remainingSavingsMinor, 0),
            progress: min(Double(remainingSavingsMinor) / Double(goalTargetMinor), 1),
            monthlyRequiredMinor: 0,
            deadlineBalanceMinor: afterDeadlineBalanceMinor,
            monthsToDeadline: FinancialCalendar.monthsWithDeposits(from: evaluationDate, through: goalTargetDate),
            status: .fundedNow,
            completionProjection: GoalCompletionProjection(kind: afterCompletionKind, months: afterCompletionMonths, date: afterCompletionDate)
        )
        let result = PurchaseImpactResult(
            baseline: baseline,
            afterPurchase: after,
            remainingSavingsMinor: remainingSavingsMinor,
            deadlineBalanceBeforeMinor: baselineDeadlineBalanceMinor,
            deadlineBalanceAfterMinor: afterDeadlineBalanceMinor,
            purchaseDelay: PurchaseImpactMetric(kind: delayKind, months: delayMonths, amount: 0),
            extraMonthlySavings: PurchaseImpactMetric(kind: extraMonthlyKind, months: 0, amount: extraMonthlyMinor),
            maximumPurchasePreservingDeadline: PurchaseImpactMetric(kind: maximumPurchaseKind, months: 0, amount: maximumPurchaseMinor)
        )
        return PurchaseImpactEvaluation(
            id: evaluationID,
            purchaseName: purchaseName,
            purchaseAmountMinor: purchaseAmountMinor,
            currencyCode: currencyCode,
            goalID: goalID,
            goalName: goalName,
            goalTargetMinor: goalTargetMinor,
            goalTargetDate: goalTargetDate,
            originalSavingsMinor: originalSavingsMinor,
            originalIncomeMinor: originalIncomeMinor,
            originalExpensesMinor: originalExpensesMinor,
            evaluationDate: evaluationDate,
            result: result
        )
    }
}

extension GoalCompletionProjection {
    //SwiftData cannot directly store enum associated values here, so the
    // projection is stored as simple kind/month/date fields.
    var storageKind: String {
        switch self {
        case .completedNow: "completedNow"
        case .projected: "projected"
        case .noPositiveSavingsCapacity: "noPositiveSavingsCapacity"
        case .beyondLimit: "beyondLimit"
        }
    }

    var storageMonths: Int {
        if case .projected(let months, _) = self { months } else { 0 }
    }

    var storageDate: Date? {
        if case .projected(_, let date) = self { date } else { nil }
    }

    init(kind: String, months: Int, date: Date?) {
        switch kind {
        case "completedNow":
            self = .completedNow
        case "projected":
            self = .projected(months: months, date: date ?? Date.distantFuture)
        case "noPositiveSavingsCapacity":
            self = .noPositiveSavingsCapacity
        default:
            self = .beyondLimit
        }
    }
}

extension PurchaseImpactMetric {
    // Same idea as completion projections: store rich enum values as flat fields.
    var storageKind: String {
        switch self {
        case .amount: "amount"
        case .months: "months"
        case .unavailable(let reason): "unavailable:\(reason.rawValue)"
        }
    }

    var storageMonths: Int {
        if case .months(let months) = self { months } else { 0 }
    }

    var storageAmount: Int64 {
        if case .amount(let amount) = self { amount } else { 0 }
    }

    init(kind: String, months: Int, amount: Int64) {
        if kind == "amount" {
            self = .amount(amount)
        } else if kind == "months" {
            self = .months(months)
        } else {
            let raw = kind.replacingOccurrences(of: "unavailable:", with: "")
            self = .unavailable(PurchaseImpactUnavailableReason(rawValue: raw) ?? .arithmeticOverflow)
        }
    }
}

extension GoalFundingStatus {
    // Human-readable status labels captured with the saved snapshot.
    var summaryTitle: String {
        switch self {
        case .fundedNow:
            "Funded now"
        case .onTrack:
            "On track"
        case .atRisk:
            "At risk"
        case .noContributionBeforeDeadline:
            "No deposit before deadline"
        case .pastDeadline:
            "Past deadline"
        case .nonpositiveCapacity:
            "No savings capacity"
        case .invalidInputs:
            "Invalid inputs"
        case .overflow:
            "Calculation overflow"
        case .completionBeyondLimit:
            "Beyond projection limit"
        }
    }
}
