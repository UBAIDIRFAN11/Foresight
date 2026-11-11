import Foundation
import SwiftData

//Defines how purchase evaluations are stored permanently in SwiftData.

@Model
final class SavedDecision {
    //saved decisions are flat snapshots. They intentionally copy goal/profile
    // values so History remains readable after later edits or deletion.
    @Attribute(.unique) var evaluationID: UUID
    var savedAt: Date
    var purchaseName: String
    var purchaseAmountMinor: Int64
    var originalPurchaseAmountMinor: Int64? = nil
    var originalPurchaseCurrencyCode: String? = nil
    var exchangeRateString: String? = nil
    var exchangeRateObservationDate: Date? = nil
    var exchangeRateFetchedAt: Date? = nil
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
        self.originalPurchaseAmountMinor = evaluation.conversion?.originalAmountMinor
        self.originalPurchaseCurrencyCode = evaluation.conversion?.exchangeRate.base
        self.exchangeRateString = evaluation.conversion?.exchangeRate.rateString
        self.exchangeRateObservationDate = evaluation.conversion?.exchangeRate.observationDate
        self.exchangeRateFetchedAt = evaluation.conversion?.exchangeRate.fetchedAt
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
    var conversion: PurchaseConversion? = nil

    var originalAmountMinor: Int64 { conversion?.originalAmountMinor ?? purchaseAmountMinor }
    var originalCurrencyCode: String { conversion?.exchangeRate.base ?? currencyCode }

    func convertedCost(for originalMinor: Int64) throws -> Int64 {
        try CurrencyConversion.convert(
            originalMinor,
            from: CurrencyDefinition.definition(for: originalCurrencyCode),
            to: CurrencyDefinition.definition(for: currencyCode),
            rate: conversion?.exchangeRate.rate ?? 1,
            availableSavings: originalSavingsMinor
        )
    }

    func adjustingOriginalAmount(_ originalMinor: Int64) throws -> PurchaseImpactEvaluation {
        guard originalMinor != originalAmountMinor else { return self }
        let converted = try convertedCost(for: originalMinor)
        let inputs = FinancialInputs(savingsMinor: originalSavingsMinor, incomeMinor: originalIncomeMinor,
                                     expensesMinor: originalExpensesMinor, targetMinor: goalTargetMinor,
                                     evaluationDate: evaluationDate, targetDate: goalTargetDate)
        let result = try PurchaseImpactCalculator.evaluate(PurchaseImpactInputs(financialInputs: inputs, purchaseAmountMinor: converted)).get()
        return PurchaseImpactEvaluation(
            id: UUID(), purchaseName: purchaseName, purchaseAmountMinor: converted, currencyCode: currencyCode,
            goalID: goalID, goalName: goalName, goalTargetMinor: goalTargetMinor, goalTargetDate: goalTargetDate,
            originalSavingsMinor: originalSavingsMinor, originalIncomeMinor: originalIncomeMinor,
            originalExpensesMinor: originalExpensesMinor, evaluationDate: evaluationDate, result: result,
            conversion: conversion.map { PurchaseConversion(originalAmountMinor: originalMinor, exchangeRate: $0.exchangeRate) }
        )
    }
}

extension SavedDecision {
    var conversion: PurchaseConversion? {
        guard let originalPurchaseAmountMinor, originalPurchaseAmountMinor > 0,
              let originalPurchaseCurrencyCode, !originalPurchaseCurrencyCode.isEmpty,
              let exchangeRateString,
              exchangeRateString.range(of: #"\A[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\z"#, options: .regularExpression) != nil,
              let rate = Decimal(string: exchangeRateString, locale: Locale(identifier: "en_US_POSIX")),
              !rate.isNaN, rate > 0,
              let exchangeRateObservationDate, let exchangeRateFetchedAt else { return nil }
        return PurchaseConversion(originalAmountMinor: originalPurchaseAmountMinor,
                                  exchangeRate: ExchangeRate(base: originalPurchaseCurrencyCode, quote: currencyCode, rate: rate,
                                                             observationDate: exchangeRateObservationDate, fetchedAt: exchangeRateFetchedAt))
    }

    var evaluationSnapshot: PurchaseImpactEvaluation? {
        // Unknown or incomplete stored values must not become plausible-looking results.
        let savedConversion = conversion
        guard !hasConversionMetadata || savedConversion != nil,
              goalTargetMinor > 0, originalSavingsMinor >= 0, remainingSavingsMinor >= 0,
              originalIncomeMinor >= 0, originalExpensesMinor >= 0,
              let baselineProjection = GoalCompletionProjection(kind: baselineCompletionKind, months: baselineCompletionMonths, date: baselineCompletionDate),
              let afterProjection = GoalCompletionProjection(kind: afterCompletionKind, months: afterCompletionMonths, date: afterCompletionDate),
              let baseline = snapshotCalculation(savingsMinor: originalSavingsMinor, deadlineBalanceMinor: baselineDeadlineBalanceMinor,
                                                 statusTitle: baselineStatus, projection: baselineProjection),
              let after = snapshotCalculation(savingsMinor: remainingSavingsMinor, deadlineBalanceMinor: afterDeadlineBalanceMinor,
                                              statusTitle: afterStatus, projection: afterProjection),
              let delay = PurchaseImpactMetric(kind: delayKind, months: delayMonths, amount: 0),
              let extraMonthly = PurchaseImpactMetric(kind: extraMonthlyKind, months: 0, amount: extraMonthlyMinor),
              let maximumPurchase = PurchaseImpactMetric(kind: maximumPurchaseKind, months: 0, amount: maximumPurchaseMinor) else {
            return nil
        }
        let result = PurchaseImpactResult(
            baseline: baseline,
            afterPurchase: after,
            remainingSavingsMinor: remainingSavingsMinor,
            deadlineBalanceBeforeMinor: baselineDeadlineBalanceMinor,
            deadlineBalanceAfterMinor: afterDeadlineBalanceMinor,
            purchaseDelay: delay,
            extraMonthlySavings: extraMonthly,
            maximumPurchasePreservingDeadline: maximumPurchase
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
            result: result,
            conversion: savedConversion
        )
    }

    private var hasConversionMetadata: Bool {
        originalPurchaseAmountMinor != nil || originalPurchaseCurrencyCode != nil ||
            exchangeRateString != nil || exchangeRateObservationDate != nil || exchangeRateFetchedAt != nil
    }

    private func snapshotCalculation(
        savingsMinor: Int64, deadlineBalanceMinor: Int64,
        statusTitle: String, projection: GoalCompletionProjection
    ) -> FinancialCalculationResult? {
        // Derive only unstored fields from the original inputs, never the current profile or goal.
        let months = FinancialCalendar.monthsWithDeposits(from: evaluationDate, through: goalTargetDate)
        guard let status = GoalFundingStatus(snapshotTitle: statusTitle, projection: projection,
                                            deadlineBalanceMinor: deadlineBalanceMinor, monthsToDeadline: months,
                                            targetDate: FinancialCalendar.utcNoon(for: goalTargetDate, in: FinancialCalendar.gregorianUTC)) else { return nil }
        let remaining = max(goalTargetMinor - savingsMinor, 0)
        return FinancialCalculationResult(
            monthlyCapacityMinor: originalIncomeMinor - originalExpensesMinor,
            remainingMinor: remaining,
            progress: min(Double(savingsMinor) / Double(goalTargetMinor), 1),
            monthlyRequiredMinor: status == .pastDeadline || months == 0 ? 0 : FinancialCalculator.ceilDivision(remaining, by: Int64(months)),
            deadlineBalanceMinor: deadlineBalanceMinor,
            monthsToDeadline: months,
            status: status,
            completionProjection: projection
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

    init?(kind: String, months: Int, date: Date?) {
        switch kind {
        case "completedNow":
            self = .completedNow
        case "projected":
            guard months > 0, let date else { return nil }
            self = .projected(months: months, date: date)
        case "noPositiveSavingsCapacity":
            self = .noPositiveSavingsCapacity
        case "beyondLimit":
            self = .beyondLimit
        default:
            return nil
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

    init?(kind: String, months: Int, amount: Int64) {
        if kind == "amount" {
            guard amount >= 0 else { return nil }
            self = .amount(amount)
        } else if kind == "months" {
            guard months >= 0 else { return nil }
            self = .months(months)
        } else {
            let prefix = "unavailable:"
            guard kind.hasPrefix(prefix),
                  let reason = PurchaseImpactUnavailableReason(rawValue: String(kind.dropFirst(prefix.count))) else { return nil }
            self = .unavailable(reason)
        }
    }
}

extension GoalFundingStatus {
    init?(snapshotTitle: String, projection: GoalCompletionProjection, deadlineBalanceMinor: Int64, monthsToDeadline: Int, targetDate: Date) {
        switch snapshotTitle {
        case "Funded now": self = .fundedNow
        case "On track":
            let date: Date
            if case .projected(_, let projectedDate) = projection { date = projectedDate } else { date = targetDate }
            self = .onTrack(completionDate: date, deadlineBalanceMinor: deadlineBalanceMinor, monthsToDeadline: monthsToDeadline)
        case "At risk":
            let date: Date?
            if case .projected(_, let projectedDate) = projection { date = projectedDate } else { date = nil }
            self = .atRisk(completionDate: date, deadlineBalanceMinor: deadlineBalanceMinor, monthsToDeadline: monthsToDeadline)
        case "No deposit before deadline": self = .noContributionBeforeDeadline
        case "Past deadline": self = .pastDeadline
        case "No savings capacity": self = .nonpositiveCapacity
        case "Invalid inputs": self = .invalidInputs
        case "Calculation overflow": self = .overflow
        case "Beyond projection limit": self = .completionBeyondLimit
        default: return nil
        }
    }

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
