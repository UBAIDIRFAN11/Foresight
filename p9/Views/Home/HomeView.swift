import SwiftUI
import SwiftData

struct HomeView: View {
    @Bindable var profile: FinancialProfile
    let duplicateProfileCount: Int
    // Home does not own Simulator navigation; it asks MainTabView to switch tabs.
    let onEvaluatePurchase: (UUID?) -> Void
    @Query(sort: [SortDescriptor(\FinancialGoal.targetDate), SortDescriptor(\FinancialGoal.createdAt)]) private var goals: [FinancialGoal]
    @Query(sort: [SortDescriptor(\SavedDecision.savedAt, order: .reverse)]) private var savedDecisions: [SavedDecision]
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
                    // Pass the current focus so Simulator starts on the same goal.
                    onEvaluatePurchase(focusedGoal?.id)
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
                    if let latestDecision = savedDecisions.first {
                        // Recent Decisions reuses the same read-only result view as History.
                        NavigationLink {
                            PurchaseImpactView(
                                evaluation: latestDecision.evaluationSnapshot,
                                mode: .saved(savedAt: latestDecision.savedAt),
                                onSaved: nil,
                                onAmountChange: nil,
                                onAdjust: nil
                            )
                        } label: {
                            recentDecisionRow(latestDecision)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Saved purchase decisions will appear here after you calculate and save an impact.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .foresightCard()
                    }
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
        // If the stored focus was deleted, fall back to the first sorted goal.
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

    private func recentDecisionRow(_ decision: SavedDecision) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(decision.purchaseName)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            AdaptiveValueRow(
                title: decision.goalName,
                value: MoneyFormatting.display(decision.purchaseAmountMinor, currencyCode: decision.currencyCode)
            )
            Text(decisionImpactText(decision))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foresightCard()
    }

    private func decisionImpactText(_ decision: SavedDecision) -> String {
        let snapshot = decision.evaluationSnapshot
        if let months = snapshot.result.purchaseDelay.monthCount {
            return months == 0 ? "No completion delay." : "Completion delayed by \(months) \(months == 1 ? "month" : "months")."
        }
        return "Impact estimate saved with unavailable completion delay."
    }
}

func goalSort(_ lhs: FinancialGoal, _ rhs: FinancialGoal) -> Bool {
    // Shared goal ordering: nearest deadline first, then creation date.
    if lhs.targetDate != rhs.targetDate {
        return lhs.targetDate < rhs.targetDate
    }
    if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt < rhs.createdAt
    }
    return lhs.id.uuidString < rhs.id.uuidString
}
