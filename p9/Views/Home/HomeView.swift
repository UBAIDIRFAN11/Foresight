import SwiftUI
import SwiftData

struct HomeView: View {
    @Bindable var profile: FinancialProfile
    let duplicateProfileCount: Int
    let onEvaluatePurchase: () -> Void
    @Query(sort: [SortDescriptor(\FinancialGoal.targetDate), SortDescriptor(\FinancialGoal.createdAt)]) private var goals: [FinancialGoal]
    @State private var focusedGoalID: UUID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let today = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                capacityCard

                if duplicateProfileCount > 0 {
                    Label("Multiple profiles were found. Foresight is using the earliest one and preserving the others.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .foresightCard()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Current Focus")
                        .font(.headline)
                    if sortedGoals.count > 1 {
                        Picker("Focus Goal", selection: $focusedGoalID) {
                            ForEach(sortedGoals) { goal in
                                Text(goal.name).tag(Optional(goal.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if let focusedGoal {
                        NavigationLink(value: focusedGoal.id) {
                            GoalCard(goal: focusedGoal, profile: profile, today: today)
                        }
                        .buttonStyle(.plain)
                    } else {
                        emptyFocus
                    }
                }

                Button {
                    onEvaluatePurchase()
                } label: {
                    Label("Evaluate a Purchase", systemImage: "chevron.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foresightPrimaryAction()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Decisions")
                        .font(.headline)
                    Text("To be implemented.")
                        .foregroundStyle(.secondary)
                        .foresightCard()
                }
            }
            .foresightReadableContent()
        }
        .background(ForesightTheme.background)
        .navigationDestination(for: UUID.self) { id in
            GoalDetailView(goalID: id, profile: profile)
        }
        .onAppear {
            if focusedGoalID == nil {
                focusedGoalID = sortedGoals.first?.id
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Foresight")
                .font(.largeTitle.weight(.bold))
            Text("Plan today. A brighter tomorrow.")
                .font(.title3)
        }
    }

    private var capacityCard: some View {
        let capacity = profile.monthlyIncomeMinor - profile.recurringExpensesMinor
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))

        return layout {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundStyle(ForesightTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly Savings Capacity")
                    .font(.headline)
                ViewThatFits(in: .horizontal) {
                    Text("\(MoneyFormatting.display(capacity, currencyCode: profile.preferredCurrencyCode))/month")
                        .font(.title.weight(.bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MoneyFormatting.display(capacity, currencyCode: profile.preferredCurrencyCode))
                            .font(.title.weight(.bold))
                        Text("per month")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    AdaptiveValueRow(
                        title: "Income",
                        value: MoneyFormatting.display(profile.monthlyIncomeMinor, currencyCode: profile.preferredCurrencyCode)
                    )
                    AdaptiveValueRow(
                        title: "Expenses",
                        value: MoneyFormatting.display(profile.recurringExpensesMinor, currencyCode: profile.preferredCurrencyCode)
                    )
                }
                .font(.caption)
            }
        }
        .foresightCard()
    }

    private var sortedGoals: [FinancialGoal] {
        goals.sorted(by: goalSort)
    }

    private var focusedGoal: FinancialGoal? {
        if let focusedGoalID, let goal = sortedGoals.first(where: { $0.id == focusedGoalID }) {
            return goal
        }
        return sortedGoals.first
    }

    private var emptyFocus: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "flag")
                .font(.title)
                .foregroundStyle(ForesightTheme.accent)
            Text("Add a goal to see whether your current savings plan is on track.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foresightCard()
    }
}

func goalSort(_ lhs: FinancialGoal, _ rhs: FinancialGoal) -> Bool {
    if lhs.priorityRawValue != rhs.priorityRawValue {
        return lhs.priorityRawValue > rhs.priorityRawValue
    }
    if lhs.targetDate != rhs.targetDate {
        return lhs.targetDate < rhs.targetDate
    }
    if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt < rhs.createdAt
    }
    return lhs.id.uuidString < rhs.id.uuidString
}
