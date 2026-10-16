import Foundation

//this file is responsible for producing monthly points that a chart can draw.
//it does this by being given a FinancialProfile (monthly income/savings/expenses), a goal, and optionally a purchase amount.

//each SavingsprojectionSample represents 1 point on chart
nonisolated struct SavingsProjectionSample: Identifiable, Equatable, Sendable {
    //this all tells, for example: at month 6, on this date, user would have $300 normally, or $200 after purchase.
    let date: Date
    let monthOffset: Int
    let baselineBalanceMinor: Int64
    let afterPurchaseBalanceMinor: Int64?
    let isDeadline: Bool //indicates whether a point represents the goal deadline

    var id: String {
        "\(Int(date.timeIntervalSince1970))-\(monthOffset)-\(isDeadline)"
    }
    
    
}

//this groups all the information required to draw the chart
//SavingsProjectionSample represents 1 data point, SavingsProjection represents the complete chart
nonisolated struct SavingsProjection: Equatable, Sendable {
    let samples: [SavingsProjectionSample]
    let targetMinor: Int64
    let deadlineDate: Date
    let visibleStartMonth: Int
    let visibleMonthCount: Int
    let baselineResult: FinancialCalculationResult
    let afterPurchaseResult: FinancialCalculationResult?
    let baselineCompletionMonth: Int?
    let afterPurchaseCompletionMonth: Int?
    let explanation: String?

    //determines whether an after-purchase scenario exists
    var hasComparison: Bool {
        afterPurchaseResult != nil
    }

    //determines whether earlier months are available
    var canMoveEarlier: Bool {
        visibleStartMonth > 0
    }

    //determines whether later months are available
    var canMoveLater: Bool {
        visibleStartMonth + visibleMonthCount < FinancialCalculator.completionMonthLimit
    }
}

nonisolated enum FinancialProjectionError: LocalizedError, Equatable, Sendable {
    case invalidInputs
    case invalidPurchaseAmount
    case insufficientSavings
    case arithmeticOverflow

    var errorDescription: String? {
        switch self {
        case .invalidInputs:
            "Chart unavailable because the financial inputs are invalid."
        case .invalidPurchaseAmount:
            "Chart unavailable because the purchase amount must be greater than zero."
        case .insufficientSavings:
            "Chart unavailable because this purchase is higher than current savings."
        case .arithmeticOverflow:
            "Chart unavailable because the projected balances are too large to calculate safely."
        }
    }
}

nonisolated enum FinancialProjectionBuilder {
    static let defaultVisibleMonthCount = 12

    //this function accepts financial info, opt. purchase amount, and the window of months to disp
    static func build(inputs: FinancialInputs, purchaseAmountMinor: Int64? = nil, visibleStartMonth: Int = 0, visibleMonthCount: Int = defaultVisibleMonthCount) -> Result<SavingsProjection, FinancialProjectionError> {
        
        
        let normalizedInputs = FinancialInputs(
            savingsMinor: inputs.savingsMinor,
            incomeMinor: inputs.incomeMinor,
            expensesMinor: inputs.expensesMinor,
            targetMinor: inputs.targetMinor,
            
            //normalise dates, to make date calculations consistent/avoid timezone-related date shifts
            evaluationDate: FinancialCalendar.utcNoon(for: inputs.evaluationDate, in: FinancialCalendar.gregorianUTC),
            targetDate: FinancialCalendar.utcNoon(for: inputs.targetDate, in: FinancialCalendar.gregorianUTC)
        )

        
        //calculates baseline (user's original savings info)
        let baseline = FinancialCalculator.evaluate(normalizedInputs)
        guard baseline.status != .invalidInputs else { return .failure(.invalidInputs) }
        guard baseline.status != .overflow else { return .failure(.arithmeticOverflow) }

        //calculate after purcahse (opt.)
        let afterResult: FinancialCalculationResult?
        let afterStartingMinor: Int64?
        if let purchaseAmountMinor {
            guard purchaseAmountMinor > 0 else { return .failure(.invalidPurchaseAmount) }
            guard purchaseAmountMinor <= normalizedInputs.savingsMinor else { return .failure(.insufficientSavings) }
            
            //if there is a purchase amount, subtract it from savings
            let remaining = normalizedInputs.savingsMinor.subtractingReportingOverflow(purchaseAmountMinor)
            guard !remaining.overflow else { return .failure(.arithmeticOverflow) }
            afterStartingMinor = remaining.partialValue
            let afterInputs = FinancialInputs(
                savingsMinor: remaining.partialValue,
                incomeMinor: normalizedInputs.incomeMinor,
                expensesMinor: normalizedInputs.expensesMinor,
                targetMinor: normalizedInputs.targetMinor,
                evaluationDate: normalizedInputs.evaluationDate,
                targetDate: normalizedInputs.targetDate
            )
            
            //calculate after-purchase version
            let evaluatedAfter = FinancialCalculator.evaluate(afterInputs)
            guard evaluatedAfter.status != .overflow else { return .failure(.arithmeticOverflow) }
            afterResult = evaluatedAfter
        } else {
            afterStartingMinor = nil
            afterResult = nil
        }

        let startMonth = min(max(visibleStartMonth, 0), FinancialCalculator.completionMonthLimit)
        let monthCount = max(1, min(visibleMonthCount, FinancialCalculator.completionMonthLimit))
        let endMonth = min(startMonth + monthCount, FinancialCalculator.completionMonthLimit)
        let capacity = baseline.monthlyCapacityMinor

        var samples: [SavingsProjectionSample] = []
        
        //loop through the selected months, and calculate balance for each month
        for month in startMonth...endMonth {
            guard let baselineBalance = FinancialCalculator.balance(
                startingMinor: normalizedInputs.savingsMinor,
                monthlyCapacityMinor: capacity,
                months: month
            ) else {
                return .failure(.arithmeticOverflow)
            }
            let afterBalance: Int64?
            if let afterStartingMinor {
                guard let calculatedAfter = FinancialCalculator.balance(
                    startingMinor: afterStartingMinor,
                    monthlyCapacityMinor: capacity,
                    months: month
                ) else {
                    return .failure(.arithmeticOverflow)
                }
                afterBalance = calculatedAfter
            } else {
                afterBalance = nil
            }

            let sampleDate = FinancialCalendar.clampedAnniversary(from: normalizedInputs.evaluationDate, addingMonths: month)
            samples.append(
                SavingsProjectionSample(
                    date: sampleDate,
                    monthOffset: month,
                    baselineBalanceMinor: baselineBalance,
                    afterPurchaseBalanceMinor: afterBalance,
                    isDeadline: sampleDate == normalizedInputs.targetDate
                )
            )
        }

        let deadlineMonth = FinancialCalendar.monthsWithDeposits(from: normalizedInputs.evaluationDate, through: normalizedInputs.targetDate)
        let visibleStartDate = FinancialCalendar.clampedAnniversary(from: normalizedInputs.evaluationDate, addingMonths: startMonth)
        let visibleEndDate = FinancialCalendar.clampedAnniversary(from: normalizedInputs.evaluationDate, addingMonths: endMonth)
        if normalizedInputs.targetDate >= visibleStartDate,
           normalizedInputs.targetDate <= visibleEndDate,
           !samples.contains(where: { $0.date == normalizedInputs.targetDate }) {
            guard let baselineBalance = FinancialCalculator.balance(
                startingMinor: normalizedInputs.savingsMinor,
                monthlyCapacityMinor: capacity,
                months: deadlineMonth
            ) else {
                return .failure(.arithmeticOverflow)
            }
            let afterBalance: Int64?
            if let afterStartingMinor {
                guard let calculatedAfter = FinancialCalculator.balance(
                    startingMinor: afterStartingMinor,
                    monthlyCapacityMinor: capacity,
                    months: deadlineMonth
                ) else {
                    return .failure(.arithmeticOverflow)
                }
                afterBalance = calculatedAfter
            } else {
                afterBalance = nil
            }
            samples.append(
                SavingsProjectionSample(
                    date: normalizedInputs.targetDate,
                    monthOffset: deadlineMonth,
                    baselineBalanceMinor: baselineBalance,
                    afterPurchaseBalanceMinor: afterBalance,
                    isDeadline: true
                )
            )
            samples.sort { $0.date < $1.date }
        }

        
        //package the samples, target, deadline, and calculation results into SavingsProjection and return that
        return .success(
            SavingsProjection(
                samples: samples,
                targetMinor: normalizedInputs.targetMinor,
                deadlineDate: normalizedInputs.targetDate,
                visibleStartMonth: startMonth,
                visibleMonthCount: monthCount,
                baselineResult: baseline,
                afterPurchaseResult: afterResult,
                baselineCompletionMonth: baseline.completionProjection.monthCount,
                afterPurchaseCompletionMonth: afterResult?.completionProjection.monthCount,
                explanation: explanation(for: baseline, after: afterResult)
            )
        )
    }

    static func startMonthForMilestone(_ month: Int?, visibleMonthCount: Int = defaultVisibleMonthCount) -> Int? {
        guard let month, month >= 0, month <= FinancialCalculator.completionMonthLimit else { return nil }
        let halfWindow = max(visibleMonthCount / 2, 1)
        return max(month - halfWindow, 0)
    }

    private static func explanation(for baseline: FinancialCalculationResult, after: FinancialCalculationResult?) -> String? {
        let status = after?.status ?? baseline.status
        switch status {
        case .fundedNow:
            return "This goal is already funded. The chart still shows how the balance changes over time."
        case .atRisk(let completionDate, _, _):
            if completionDate == nil {
                return "Savings are currently at or above the target, but the future balance may fall below it."
            }
            return nil
        case .pastDeadline:
            return "The deadline is in the past, so the chart focuses on the visible balance path only."
        case .nonpositiveCapacity:
            return "Monthly savings capacity is not positive, so completion may be unavailable."
        case .completionBeyondLimit:
            return "Completion is outside the 1,200-month projection limit."
        case .overflow:
            return "Projected balances are too large to calculate safely."
        case .invalidInputs:
            return "Check the profile and goal amounts before charting."
        case .noContributionBeforeDeadline, .onTrack:
            return nil
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
