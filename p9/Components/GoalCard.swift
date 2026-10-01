import SwiftUI

struct GoalCard: View {
    let goal: FinancialGoal
    let profile: FinancialProfile
    let today: Date

    private var result: FinancialCalculationResult {
        FinancialCalculator.evaluate(
            FinancialInputs(
                savingsMinor: profile.currentSavingsMinor,
                incomeMinor: profile.monthlyIncomeMinor,
                expensesMinor: profile.recurringExpensesMinor,
                targetMinor: goal.targetAmountMinor,
                evaluationDate: today,
                targetDate: goal.targetDate
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ForesightTheme.accentSoft)
                    Image(systemName: iconName)
                        .font(.title)
                        .foregroundStyle(ForesightTheme.accent)
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(goal.name)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.semibold))
                    }
                    if let goalDescription = goal.goalDescription {
                        Text(goalDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    ProgressView(value: result.progress)
                        .tint(ForesightTheme.accent)
                    Text("\(MoneyFormatting.display(profile.currentSavingsMinor, currencyCode: profile.preferredCurrencyCode)) of \(MoneyFormatting.display(goal.targetAmountMinor, currencyCode: profile.preferredCurrencyCode))")
                        .font(.subheadline.weight(.semibold))
                }
            }

            HStack {
                Label(formattedTargetDate, systemImage: "calendar")
                Spacer()
                GoalStatusBadge(result: result)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Text("Required each month")
                Spacer()
                Text(MoneyFormatting.display(result.monthlyRequiredMinor, currencyCode: profile.preferredCurrencyCode))
                    .fontWeight(.bold)
            }
            .font(.footnote)
        }
        .foresightCard()
    }

    private var iconName: String {
        switch goal.priority {
        case .high: "star.fill"
        case .medium: "flag.fill"
        case .low: "leaf.fill"
        }
    }

    private var formattedTargetDate: String {
        FinancialCalendar.displayDate(fromUTCNoon: goal.targetDate)
            .formatted(.dateTime.day().month(.abbreviated).year())
    }
}
