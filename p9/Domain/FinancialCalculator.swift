import Foundation

nonisolated enum FinancialCalculator {
    static let completionMonthLimit = 1_200

    static func evaluate(_ inputs: FinancialInputs) -> FinancialCalculationResult {
        guard inputs.targetMinor > 0, inputs.savingsMinor >= 0, inputs.incomeMinor >= 0, inputs.expensesMinor >= 0 else {
            return invalidResult(capacity: inputs.incomeMinor - inputs.expensesMinor)
        }

        let evaluationDate = FinancialCalendar.utcNoon(for: inputs.evaluationDate, in: FinancialCalendar.gregorianUTC)
        let targetDate = FinancialCalendar.utcNoon(for: inputs.targetDate, in: FinancialCalendar.gregorianUTC)
        let capacity = inputs.incomeMinor - inputs.expensesMinor
        let remaining = max(inputs.targetMinor - inputs.savingsMinor, 0)
        let progress = min(Double(inputs.savingsMinor) / Double(inputs.targetMinor), 1.0)
        let monthsToDeadline = FinancialCalendar.monthsWithDeposits(from: evaluationDate, through: targetDate)
        let monthlyRequired = ceilDivision(remaining, by: Int64(max(monthsToDeadline, 1)))
        let deadlineBalance = balance(startingMinor: inputs.savingsMinor, monthlyCapacityMinor: capacity, months: monthsToDeadline)

        guard let deadlineBalance else {
            return .init(
                monthlyCapacityMinor: capacity,
                remainingMinor: remaining,
                progress: progress,
                monthlyRequiredMinor: monthlyRequired,
                deadlineBalanceMinor: inputs.savingsMinor,
                monthsToDeadline: monthsToDeadline,
                status: .overflow
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
                status: .pastDeadline
            )
        }

        let completionDate = completionDate(remainingMinor: remaining, capacityMinor: capacity, evaluationDate: evaluationDate)
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
            status = .onTrack(completionDate: completionDate ?? targetDate, deadlineBalanceMinor: deadlineBalance, monthsToDeadline: monthsToDeadline)
        } else if completionDate == nil {
            status = .completionBeyondLimit
        } else {
            status = .atRisk(completionDate: completionDate, deadlineBalanceMinor: deadlineBalance, monthsToDeadline: monthsToDeadline)
        }

        return .init(
            monthlyCapacityMinor: capacity,
            remainingMinor: remaining,
            progress: progress,
            monthlyRequiredMinor: monthsToDeadline == 0 ? 0 : monthlyRequired,
            deadlineBalanceMinor: deadlineBalance,
            monthsToDeadline: monthsToDeadline,
            status: status
        )
    }

    static func balance(startingMinor: Int64, monthlyCapacityMinor: Int64, months: Int) -> Int64? {
        guard months >= 0 else { return nil }
        let monthly = monthlyCapacityMinor.multipliedReportingOverflow(by: Int64(months))
        guard !monthly.overflow else { return nil }
        let total = startingMinor.addingReportingOverflow(monthly.partialValue)
        return total.overflow ? nil : total.partialValue
    }

    static func advanceBalance(_ balance: Int64, byMonthlyCapacity capacity: Int64, months: Int) -> Int64? {
        self.balance(startingMinor: balance, monthlyCapacityMinor: capacity, months: months)
    }

    private static func completionDate(remainingMinor: Int64, capacityMinor: Int64, evaluationDate: Date) -> Date? {
        guard remainingMinor > 0 else { return evaluationDate }
        guard capacityMinor > 0 else { return nil }
        let months = ceilDivision(remainingMinor, by: capacityMinor)
        guard months <= completionMonthLimit else { return nil }
        return FinancialCalendar.clampedAnniversary(from: evaluationDate, addingMonths: Int(months))
    }

    private static func ceilDivision(_ numerator: Int64, by denominator: Int64) -> Int64 {
        guard numerator > 0, denominator > 0 else { return 0 }
        let adjusted = numerator.addingReportingOverflow(denominator - 1)
        guard !adjusted.overflow else { return Int64.max }
        return adjusted.partialValue / denominator
    }

    private static func invalidResult(capacity: Int64) -> FinancialCalculationResult {
        .init(
            monthlyCapacityMinor: capacity,
            remainingMinor: 0,
            progress: 0,
            monthlyRequiredMinor: 0,
            deadlineBalanceMinor: 0,
            monthsToDeadline: 0,
            status: .invalidInputs
        )
    }
}
