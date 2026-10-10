import SwiftUI

struct GoalCard: View {
    let goal: FinancialGoal
    let profile: FinancialProfile
    let today: Date
    let showsNavigationIndicator: Bool

    init(goal: FinancialGoal, profile: FinancialProfile, today: Date, showsNavigationIndicator: Bool = true) {
        self.goal = goal
        self.profile = profile
        self.today = today
        self.showsNavigationIndicator = showsNavigationIndicator
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var iconSize = 82

    private var result: FinancialCalculationResult {
        // Goal cards always show the latest calculation from the current profile.
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
            // At accessibility text sizes the card stacks vertically for readability.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

            layout {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ForesightTheme.accentSoft)
                    Image(systemName: iconName)
                        .font(.title)
                        .foregroundStyle(ForesightTheme.accent)
                }
                .frame(width: iconSize, height: iconSize)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(goal.name)
                            .font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if showsNavigationIndicator {
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let goalDescription = goal.goalDescription {
                        Text(goalDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ProgressView(value: result.progress)
                        .tint(ForesightTheme.accent)
                    Text("\(MoneyFormatting.display(profile.currentSavingsMinor, currencyCode: profile.preferredCurrencyCode)) of \(MoneyFormatting.display(goal.targetAmountMinor, currencyCode: profile.preferredCurrencyCode))")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ViewThatFits(in: .horizontal) {
                // Date and status sit together when there is room, otherwise stack.
                HStack(alignment: .firstTextBaseline) {
                    Label(formattedTargetDate, systemImage: "calendar")
                    Spacer(minLength: 12)
                    GoalStatusBadge(result: result)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(formattedTargetDate, systemImage: "calendar")
                    GoalStatusBadge(result: result)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .foresightCard()
    }

    private var iconName: String {
        "flag.fill"
    }

    private var formattedTargetDate: String {
        FinancialCalendar.displayDate(fromUTCNoon: goal.targetDate)
            .formatted(.dateTime.day().month(.abbreviated).year())
    }
}
