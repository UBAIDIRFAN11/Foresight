import Foundation

nonisolated enum PurchaseImpactCalculator {
    static func evaluate(_ inputs: PurchaseImpactInputs) -> Result<PurchaseImpactResult, PurchaseImpactError> {
        let financial = inputs.financialInputs
        guard financial.targetMinor > 0, financial.savingsMinor >= 0, financial.incomeMinor >= 0, financial.expensesMinor >= 0 else {
            return .failure(.invalidFinancialInputs)
        }
        guard inputs.purchaseAmountMinor > 0 else {
            return .failure(.invalidPurchaseAmount)
        }
        guard inputs.purchaseAmountMinor <= financial.savingsMinor else {
            return .failure(.insufficientSavings)
        }

        let remainingSavings = financial.savingsMinor.subtractingReportingOverflow(inputs.purchaseAmountMinor)
        guard !remainingSavings.overflow else {
            return .failure(.arithmeticOverflow)
        }

        let baseline = FinancialCalculator.evaluate(financial)
        guard baseline.status != .invalidInputs, baseline.status != .overflow else {
            return .failure(baseline.status == .overflow ? .arithmeticOverflow : .invalidFinancialInputs)
        }

        let afterInputs = FinancialInputs(
            savingsMinor: remainingSavings.partialValue,
            incomeMinor: financial.incomeMinor,
            expensesMinor: financial.expensesMinor,
            targetMinor: financial.targetMinor,
            evaluationDate: financial.evaluationDate,
            targetDate: financial.targetDate
        )
        let afterPurchase = FinancialCalculator.evaluate(afterInputs)
        guard afterPurchase.status != .overflow else {
            return .failure(.arithmeticOverflow)
        }

        let result = PurchaseImpactResult(
            baseline: baseline,
            afterPurchase: afterPurchase,
            remainingSavingsMinor: remainingSavings.partialValue,
            deadlineBalanceBeforeMinor: baseline.deadlineBalanceMinor,
            deadlineBalanceAfterMinor: afterPurchase.deadlineBalanceMinor,
            purchaseDelay: delay(before: baseline.completionProjection, after: afterPurchase.completionProjection),
            extraMonthlySavings: extraMonthlySavings(for: afterPurchase, targetMinor: financial.targetMinor),
            maximumPurchasePreservingDeadline: maximumPurchase(for: baseline, savingsMinor: financial.savingsMinor, targetMinor: financial.targetMinor)
        )
        return .success(result)
    }

    private static func delay(before: GoalCompletionProjection, after: GoalCompletionProjection) -> PurchaseImpactMetric {
        guard let beforeMonths = before.monthCount, let afterMonths = after.monthCount else {
            return .unavailable(unavailableReason(for: after))
        }
        return .months(max(afterMonths - beforeMonths, 0))
    }

    private static func extraMonthlySavings(for result: FinancialCalculationResult, targetMinor: Int64) -> PurchaseImpactMetric {
        if result.status == .pastDeadline {
            return .unavailable(.pastDeadline)
        }
        let shortfall = targetMinor.subtractingReportingOverflow(result.deadlineBalanceMinor)
        guard !shortfall.overflow else {
            return .unavailable(.arithmeticOverflow)
        }
        let needed = max(shortfall.partialValue, 0)
        guard needed > 0 else {
            return .amount(0)
        }
        guard result.monthsToDeadline > 0 else {
            return .unavailable(.noDepositsBeforeDeadline)
        }
        return .amount(FinancialCalculator.ceilDivision(needed, by: Int64(result.monthsToDeadline)))
    }

    private static func maximumPurchase(for baseline: FinancialCalculationResult, savingsMinor: Int64, targetMinor: Int64) -> PurchaseImpactMetric {
        if baseline.status == .pastDeadline {
            return .unavailable(.pastDeadline)
        }
        guard baseline.deadlineBalanceMinor >= targetMinor else {
            return .unavailable(.currentPlanAlreadyMissesDeadline)
        }
        let cushion = baseline.deadlineBalanceMinor.subtractingReportingOverflow(targetMinor)
        guard !cushion.overflow else {
            return .unavailable(.arithmeticOverflow)
        }
        return .amount(min(savingsMinor, cushion.partialValue))
    }

    private static func unavailableReason(for projection: GoalCompletionProjection) -> PurchaseImpactUnavailableReason {
        switch projection {
        case .completedNow, .projected:
            .notNeeded
        case .noPositiveSavingsCapacity:
            .noPositiveSavingsCapacity
        case .beyondLimit:
            .projectionBeyondLimit
        }
    }
}

private extension GoalCompletionProjection {
    nonisolated var monthCount: Int? {
        switch self {
        case .completedNow:
            0
        case .projected(let months, _):
            months
        case .noPositiveSavingsCapacity, .beyondLimit:
            nil
        }
    }
}
