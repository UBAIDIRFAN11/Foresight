import Foundation

//The main deterministic calculation engine.
//It determines whether a user can achieve a savings goal by its deadline.

nonisolated enum FinancialCalculator {
    static let completionMonthLimit = 1_200

    static func evaluate(_ inputs: FinancialInputs) -> FinancialCalculationResult {
        
        //monthly capacity = income - expenses
        let capacityResult = inputs.incomeMinor.subtractingReportingOverflow(inputs.expensesMinor)
        guard !capacityResult.overflow else {
            return invalidResult(capacity: 0)
        }
        let capacity = capacityResult.partialValue

        guard inputs.targetMinor > 0, inputs.savingsMinor >= 0, inputs.incomeMinor >= 0, inputs.expensesMinor >= 0 else {
            return invalidResult(capacity: capacity)
        }

        let evaluationDate = FinancialCalendar.utcNoon(for: inputs.evaluationDate, in: FinancialCalendar.gregorianUTC)
        let targetDate = FinancialCalendar.utcNoon(for: inputs.targetDate, in: FinancialCalendar.gregorianUTC)
        
        //remaining = target − current savings
        let targetRemaining = inputs.targetMinor.subtractingReportingOverflow(inputs.savingsMinor)
        guard !targetRemaining.overflow else {
            return invalidResult(capacity: capacity)
        }
        let remaining = max(targetRemaining.partialValue, 0)
        
        // calculate progress: i.e. how much of the goal is already funded
        let progress = min(Double(inputs.savingsMinor) / Double(inputs.targetMinor), 1.0)
        
        //calculate how many months left until deadline date (from current date)
        let monthsToDeadline = FinancialCalendar.monthsWithDeposits(from: evaluationDate, through: targetDate)
        
        //monthlyRequired = how much must be saved each month
        let monthlyRequired = ceilDivision(remaining, by: Int64(max(monthsToDeadline, 1)))
        
        //deadlineBalance = projected savings by the deadline
        let deadlineBalance = balance(startingMinor: inputs.savingsMinor, monthlyCapacityMinor: capacity, months: monthsToDeadline)
        
        //completionProjection = when the goal will actually be reached
        let projection = completionProjection(startingMinor: inputs.savingsMinor, targetMinor: inputs.targetMinor, capacityMinor: capacity, evaluationDate: evaluationDate)

        guard let deadlineBalance else {
            return .init(
                monthlyCapacityMinor: capacity,
                remainingMinor: remaining,
                progress: progress,
                monthlyRequiredMinor: monthlyRequired,
                deadlineBalanceMinor: inputs.savingsMinor,
                monthsToDeadline: monthsToDeadline,
                status: .overflow,
                completionProjection: projection
            )
        }

        if FinancialCalendar.isBeforeDay(targetDate, evaluationDate) {
            return .init(
                monthlyCapacityMinor: capacity,
                remainingMinor: remaining,
                progress: progress,
                monthlyRequiredMinor: 0,
                deadlineBalanceMinor: inputs.savingsMinor,
                monthsToDeadline: 0,
                status: .pastDeadline,
                completionProjection: projection
            )
        }

        //determine state: e.g. if goal is ontrack, at risk
        let status: GoalFundingStatus
        if remaining == 0 {
            status = deadlineBalance >= inputs.targetMinor
                ? .fundedNow
                : .atRisk(completionDate: nil, deadlineBalanceMinor: deadlineBalance, monthsToDeadline: monthsToDeadline)
        } else if monthsToDeadline == 0 {
            status = .noContributionBeforeDeadline
        } else if capacity <= 0 {
            status = .nonpositiveCapacity
        } else if deadlineBalance >= inputs.targetMinor {
            status = .onTrack(completionDate: projection.date ?? targetDate, deadlineBalanceMinor: deadlineBalance, monthsToDeadline: monthsToDeadline)
        } else if projection.date == nil {
            status = .completionBeyondLimit
        } else {
            status = .atRisk(completionDate: projection.date, deadlineBalanceMinor: deadlineBalance, monthsToDeadline: monthsToDeadline)
        }

        return .init(
            monthlyCapacityMinor: capacity,
            remainingMinor: remaining,
            progress: progress,
            monthlyRequiredMinor: monthsToDeadline == 0 ? 0 : monthlyRequired,
            deadlineBalanceMinor: deadlineBalance,
            monthsToDeadline: monthsToDeadline,
            status: status,
            completionProjection: projection
        )
    }

    static func balance(startingMinor: Int64, monthlyCapacityMinor: Int64, months: Int) -> Int64? {
        guard months >= 0 else { return nil }
        // Return nil instead of wrapping if the projected balance is too large.
        let monthly = monthlyCapacityMinor.multipliedReportingOverflow(by: Int64(months))
        guard !monthly.overflow else { return nil }
        let total = startingMinor.addingReportingOverflow(monthly.partialValue)
        return total.overflow ? nil : total.partialValue
    }

    static func advanceBalance(_ balance: Int64, byMonthlyCapacity capacity: Int64, months: Int) -> Int64? {
        self.balance(startingMinor: balance, monthlyCapacityMinor: capacity, months: months)
    }

    static func completionProjection(startingMinor: Int64, targetMinor: Int64, capacityMinor: Int64, evaluationDate: Date) -> GoalCompletionProjection {
        guard targetMinor > 0, startingMinor >= 0 else { return .beyondLimit }
        let remainingResult = targetMinor.subtractingReportingOverflow(startingMinor)
        guard !remainingResult.overflow else { return .beyondLimit }
        let remainingMinor = max(remainingResult.partialValue, 0)
        guard remainingMinor > 0 else { return .completedNow }
        guard capacityMinor > 0 else { return .noPositiveSavingsCapacity }
        let months = ceilDivision(remainingMinor, by: capacityMinor)
        // Keep long projections bounded so the UI does not imply certainty forever.
        guard months <= completionMonthLimit else { return .beyondLimit }
        return .projected(months: Int(months), date: FinancialCalendar.clampedAnniversary(from: evaluationDate, addingMonths: Int(months)))
    }

    static func ceilDivision(_ numerator: Int64, by denominator: Int64) -> Int64 {
        guard numerator > 0, denominator > 0 else { return 0 }
        // Quotient/remainder avoids the overflow risk of numerator + denominator - 1.
        let quotient = numerator / denominator
        let remainder = numerator % denominator
        guard remainder > 0 else { return quotient }
        let rounded = quotient.addingReportingOverflow(1)
        return rounded.overflow ? Int64.max : rounded.partialValue
    }

    private static func invalidResult(capacity: Int64) -> FinancialCalculationResult {
        .init(
            monthlyCapacityMinor: capacity,
            remainingMinor: 0,
            progress: 0,
            monthlyRequiredMinor: 0,
            deadlineBalanceMinor: 0,
            monthsToDeadline: 0,
            status: .invalidInputs,
            completionProjection: .beyondLimit
        )
    }
}

private extension GoalCompletionProjection {
    nonisolated var date: Date? {
        if case .projected(_, let date) = self { date } else { nil }
    }
}
