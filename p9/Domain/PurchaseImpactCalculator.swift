import Foundation

//This purchaseimpactcalculator's job is to answer: “If I make this purchase right now, what happens to my financial goal?”
//It does this by calculating the goal before the purchase, calculating it again after the purchase, and comparing the two.

nonisolated enum PurchaseImpactCalculator {
    

    static func evaluate(_ inputs: PurchaseImpactInputs) -> Result<PurchaseImpactResult, PurchaseImpactError> {
        
        //get user's financial situation
        //Validate inputs
        let financial = inputs.financialInputs
        guard financial.targetMinor > 0, financial.savingsMinor >= 0, financial.incomeMinor >= 0, financial.expensesMinor >= 0 else {
            return .failure(.invalidFinancialInputs)
        }
        
        //purchase amount >0
        guard inputs.purchaseAmountMinor > 0 else {
            return .failure(.invalidPurchaseAmount)
        }
        
        //purchase amount must be <= user's current savings
        guard inputs.purchaseAmountMinor <= financial.savingsMinor else {
            return .failure(.insufficientSavings)
        }

        //the purchase is hypothetical: calculate a savings value without affecting the real profile
        //remaining savings = current savings - purchase amount
        let remainingSavings = financial.savingsMinor.subtractingReportingOverflow(inputs.purchaseAmountMinor)
        guard !remainingSavings.overflow else {
            return .failure(.arithmeticOverflow)
        }

        //Calculate baseline: what happens to the goal if user doesn't make this purchase
        let baseline = FinancialCalculator.evaluate(financial)
        guard baseline.status != .invalidInputs, baseline.status != .overflow else {
            return .failure(baseline.status == .overflow ? .arithmeticOverflow : .invalidFinancialInputs)
        }

        //afterinputs: all the same financial profile info, but now with curr savings reduced (due to the purchase)
        let afterInputs = FinancialInputs(
            savingsMinor: remainingSavings.partialValue,
            incomeMinor: financial.incomeMinor,
            expensesMinor: financial.expensesMinor,
            targetMinor: financial.targetMinor,
            evaluationDate: financial.evaluationDate,
            targetDate: financial.targetDate
        )
        //re-run the same goal calculation with the hypothetical savings amount.
        let afterPurchase = FinancialCalculator.evaluate(afterInputs)
        guard afterPurchase.status != .overflow else {
            return .failure(.arithmeticOverflow)
        }

        //Return purchase impact
        let result = PurchaseImpactResult(
            baseline: baseline,
            afterPurchase: afterPurchase,
            remainingSavingsMinor: remainingSavings.partialValue,
            
            //Compare before vs after
            deadlineBalanceBeforeMinor: baseline.deadlineBalanceMinor,
            deadlineBalanceAfterMinor: afterPurchase.deadlineBalanceMinor,
            
            //how much delay is caused from the purchase (if any)
            purchaseDelay: delay(before: baseline.completionProjection, after: afterPurchase.completionProjection),
            
            //how much more will need to be earned after purchase to still meeet deadline for goal
            extraMonthlySavings: extraMonthlySavings(for: afterPurchase, targetMinor: financial.targetMinor),
            
            //maximum amount that can be spent and still achieve goal by deadline
            maximumPurchasePreservingDeadline: maximumPurchase(for: baseline, savingsMinor: financial.savingsMinor, targetMinor: financial.targetMinor)
        )
        return .success(result)
    }
    

    private static func delay(before: GoalCompletionProjection, after: GoalCompletionProjection) -> PurchaseImpactMetric {
        //delay is only meaningful when both projections have finite month counts.
        guard let beforeMonths = before.monthCount, let afterMonths = after.monthCount else {
            return .unavailable(unavailableReason(for: after))
        }
        
        //calculates delay by subtracting number of months to complete goal (before purchase) from number of months to complete goal (after purchase)
        return .months(max(afterMonths - beforeMonths, 0))
    }

    //calculates how much extra money per month user needs to save after purchase to still hit goal target by deadline.
    private static func extraMonthlySavings(for result: FinancialCalculationResult, targetMinor: Int64) -> PurchaseImpactMetric {
        
        //if goal deadline is already in past, cannot recommend extra monthly savings for that deadline
        if result.status == .pastDeadline {
            return .unavailable(.pastDeadline)
        }
        
        //shortfall = target amount - amount at deadline
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
        //round up so the recommendation actually reaches the target.
        return .amount(FinancialCalculator.ceilDivision(needed, by: Int64(result.monthsToDeadline)))
    }

    private static func maximumPurchase(for baseline: FinancialCalculationResult, savingsMinor: Int64, targetMinor: Int64) -> PurchaseImpactMetric {
        if baseline.status == .pastDeadline {
            return .unavailable(.pastDeadline)
        }
        guard baseline.deadlineBalanceMinor >= targetMinor else {
            return .unavailable(.currentPlanAlreadyMissesDeadline)
        }
        //only the existing deadline cushion can be safely spent.
        let cushion = baseline.deadlineBalanceMinor.subtractingReportingOverflow(targetMinor)
        guard !cushion.overflow else {
            return .unavailable(.arithmeticOverflow)
        }
        
        //max purchase is the smaller of curr savings, deadline cushion, as even if large deadline cushion, user cant spend more than current savings.
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
