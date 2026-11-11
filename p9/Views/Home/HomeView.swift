import SwiftUI
import SwiftData

//displays user's financial overview, focused goal, recent purchase decisions

struct HomeView: View {
    @Bindable var profile: FinancialProfile
    let duplicateProfileCount: Int
    let evaluationDay: Date
    
    // Home does not own Simulator navigation; it asks MainTabView to switch tabs.
    let onEvaluatePurchase: (UUID?) -> Void
    
    //retrieves goal and decision entries from SwiftData db
    @Query(sort: [SortDescriptor(\FinancialGoal.targetDate), SortDescriptor(\FinancialGoal.createdAt)]) private var goals: [FinancialGoal]
    
    //decisions sorted newest first
    @Query(sort: [SortDescriptor(\SavedDecision.savedAt, order: .reverse)]) private var savedDecisions: [SavedDecision]
    
    @EnvironmentObject private var router: AppRouter
    @State private var focus = HomeFocusSelection()
    @State private var isChoosingFocusGoal = false
    @AccessibilityFocusState private var focusChooserFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var today: Date { evaluationDay }

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
                        .accessibilityAddTraits(.isHeader)
                        .font(.headline)
                    if sortedGoals.count > 1 {
                        Button {
                            isChoosingFocusGoal = true
                        } label: {
                            Label("Change Focus Goal", systemImage: "arrow.left.arrow.right")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityValue(focusedGoal?.name ?? "")
                        .accessibilityHint("Shows each goal's target and deadline.")
                        .accessibilityFocused($focusChooserFocused)
                    }
                    if let focusedGoal {
                        NavigationLink(value: focusedGoal.id) {
                            GoalCard(goal: focusedGoal, profile: profile, today: today)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens goal details.")
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
                .accessibilityHint("Opens the Simulator with your current focus goal.")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Decisions")
                        .accessibilityAddTraits(.isHeader)
                        .font(.headline)
                    if let latestDecision = savedDecisions.first {
                        // Recent Decisions reuses the same read-only result view as History.
                        NavigationLink {
                            if let snapshot = latestDecision.evaluationSnapshot {
                                PurchaseImpactView(
                                    evaluation: snapshot,
                                    mode: .saved(savedAt: latestDecision.savedAt),
                                    onSaved: nil,
                                    onAmountChange: nil,
                                    onAdjust: nil,
                                    onReevaluate: { prefill in
                                        router.prefillSimulator(prefill)
                                    }
                                )
                            } else {
                                ContentUnavailableView(
                                    "Decision Unavailable",
                                    systemImage: "questionmark.folder",
                                    description: Text("The original result could not be restored.")
                                )
                            }
                        } label: {
                            recentDecisionRow(latestDecision)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the saved purchase analysis.")
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
            GoalDetailView(goalID: id, profile: profile, evaluationDay: evaluationDay)
        }
        .sheet(isPresented: $isChoosingFocusGoal, onDismiss: {
            // Only restore focus if the opener still exists on the visible Home screen.
            if sortedGoals.count > 1, router.selectedTab == .home { focusChooserFocused = true }
        }) {
            NavigationStack {
                // Home always shows a goal when one exists, so there is no "none" choice here.
                GoalSelectionSheet(navigationTitle: "Focus Goal", profile: profile, evaluationDay: evaluationDay,
                                   selectedID: focus.selectedID) { id in
                    focus.selectedID = id
                }
            }
        }
        //keep focused goal on Home synced with user's saved goals
        //runs when view initially appears, and when the goals arr changes
        .onChange(of: sortedGoals.map(\.id), initial: true) { _, ids in
            focus.reconcile(sortedIDs: ids, preferredID: profile.preferredFocusGoalID)
        }
        //when preferred goal changes, update Home's focused foal to match
        .onChange(of: profile.preferredFocusGoalID) { _, preferredID in
            focus.applyDefault(sortedIDs: sortedGoals.map(\.id), preferredID: preferredID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Foresight")
                .accessibilityAddTraits(.isHeader)
                .font(.largeTitle.weight(.bold))
            Text("Plan today. A brighter tomorrow.")
                .font(.title3)
        }
    }

    private var capacityCard: some View {
        //calculate how much user can save per month from their income - expenses
        let capacity = profile.monthlyIncomeMinor - profile.recurringExpensesMinor
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))

        return layout {
            Image(systemName: "chart.bar")
                .accessibilityHidden(true)
                .font(.largeTitle)
                .foregroundStyle(ForesightTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly Savings Capacity")
                    .font(.headline)
                
                //tries child views in order and disp 1st one that fits horizontally
                ViewThatFits(in: .horizontal) {
                    
                    //all in 1 line
                    Text("\(MoneyFormatting.display(capacity, currencyCode: profile.preferredCurrencyCode))/month")
                        .font(.title.weight(.bold))
                    
                    //2 lines
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MoneyFormatting.display(capacity, currencyCode: profile.preferredCurrencyCode))
                            .font(.title.weight(.bold))
                        Text("per month")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Monthly savings capacity")
                .accessibilityValue("\(AccessibilityMoney.spoken(capacity, currencyCode: profile.preferredCurrencyCode)) per month")

                VStack(alignment: .leading, spacing: 4) {
                    AdaptiveValueRow(
                        title: "Income",
                        value: MoneyFormatting.display(profile.monthlyIncomeMinor, currencyCode: profile.preferredCurrencyCode), spokenValue: AccessibilityMoney.spoken(profile.monthlyIncomeMinor, currencyCode: profile.preferredCurrencyCode)
                    )
                    AdaptiveValueRow(
                        title: "Expenses",
                        value: MoneyFormatting.display(profile.recurringExpensesMinor, currencyCode: profile.preferredCurrencyCode), spokenValue: AccessibilityMoney.spoken(profile.recurringExpensesMinor, currencyCode: profile.preferredCurrencyCode)
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
        sortedGoals.first { $0.id == focus.selectedID }
    }

    private var emptyFocus: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "flag")
                .accessibilityHidden(true)
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
                    .accessibilityHidden(true)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            AdaptiveValueRow(
                title: decision.goalName,
                value: MoneyFormatting.display(decision.purchaseAmountMinor, currencyCode: decision.currencyCode), spokenValue: AccessibilityMoney.spoken(decision.purchaseAmountMinor, currencyCode: decision.currencyCode)
            )
            Text(decisionImpactText(decision))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foresightCard()
    }

    private func decisionImpactText(_ decision: SavedDecision) -> String {
        guard let snapshot = decision.evaluationSnapshot else { return "Original result unavailable." }
        if let months = snapshot.result.purchaseDelay.monthCount {
            return months == 0 ? "No completion delay." : "Completion delayed by \(months) \(months == 1 ? "month" : "months")."
        }
        return "Impact estimate saved with unavailable completion delay."
    }
}

func goalSort(_ lhs: FinancialGoal, _ rhs: FinancialGoal) -> Bool {
    // Priority only organises goals; calculations remain independent.
    if lhs.priority != rhs.priority {
        return lhs.priority.rawValue > rhs.priority.rawValue
    }
    if lhs.targetDate != rhs.targetDate {
        return lhs.targetDate < rhs.targetDate
    }
    if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt < rhs.createdAt
    }
    return lhs.id.uuidString < rhs.id.uuidString
}
