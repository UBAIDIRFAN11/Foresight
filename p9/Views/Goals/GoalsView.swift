import SwiftUI
import SwiftData

struct GoalsView: View {
    enum GoalFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case onTrack = "On Track"
        case atRisk = "At Risk"
        var id: String { rawValue }
    }

    @Bindable var profile: FinancialProfile
    @Query private var goals: [FinancialGoal]
    @State private var filter: GoalFilter = .all
    @State private var isAddingGoal = false
    @AccessibilityFocusState private var addGoalFocused: Bool
    @Namespace private var goalsRotor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let evaluationDay: Date
    private var today: Date { evaluationDay }

    var body: some View {
        let displayedGoals = filteredGoals
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if dynamicTypeSize.isAccessibilitySize {
                        // Segmented controls get crowded at large text sizes, so use a menu.
                        Menu {
                            Picker("Filter", selection: $filter) {
                                ForEach(GoalFilter.allCases) { option in
                                    Text("\(option.rawValue) (\(count(for: option)))").tag(option)
                                }
                            }
                        } label: {
                            Label("\(filter.rawValue) (\(count(for: filter)))", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foresightCard()
                    } else {
                        Picker("Filter", selection: $filter) {
                            ForEach(GoalFilter.allCases) { option in
                                Text("\(option.rawValue) (\(count(for: option)))").tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if displayedGoals.isEmpty {
                        ContentUnavailableView("No Goals", systemImage: "flag", description: Text("Add a goal to start planning against your monthly capacity."))
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(displayedGoals) { goal in
                                NavigationLink(value: goal.id) {
                                    GoalCard(goal: goal, profile: profile, today: today)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens goal details.")
                                .id(goal.id)
                                .accessibilityRotorEntry(id: goal.id, in: goalsRotor)
                            }
                        }
                    }
                }
                .foresightReadableContent()
            }
            .accessibilityRotor("Goals") {
                ForEach(displayedGoals) { goal in
                    AccessibilityRotorEntry(Text(goal.name), id: goal.id, in: goalsRotor) {
                        // Materialize an off-screen lazy row before the rotor focuses it.
                        proxy.scrollTo(goal.id, anchor: .center)
                    }
                }
            }
        }
        .background(ForesightTheme.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingGoal = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Goal")
                .accessibilityFocused($addGoalFocused)
            }
        }
        .sheet(isPresented: $isAddingGoal, onDismiss: { addGoalFocused = true }) {
            NavigationStack {
                GoalEditorView(profile: profile, goal: nil, evaluationDay: evaluationDay)
            }
        }
        .navigationDestination(for: UUID.self) { id in
            GoalDetailView(goalID: id, profile: profile, evaluationDay: evaluationDay)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Goals")
                .accessibilityAddTraits(.isHeader)
                .font(.largeTitle.weight(.bold))
            Text("Your dreams, your timeline.")
                .font(.title3)
        }
    }

    private var sortedGoals: [FinancialGoal] {
        goals.sorted(by: goalSort)
    }

    private var filteredGoals: [FinancialGoal] {
        // Filtering is based on the live calculation for each goal.
        sortedGoals.filter { goal in
            switch filter {
            case .all:
                true
            case .onTrack:
                isOnTrack(goal)
            case .atRisk:
                !isOnTrack(goal)
            }
        }
    }

    private func count(for option: GoalFilter) -> Int {
        switch option {
        case .all: sortedGoals.count
        case .onTrack: sortedGoals.filter(isOnTrack).count
        case .atRisk: sortedGoals.filter { !isOnTrack($0) }.count
        }
    }

    private func isOnTrack(_ goal: FinancialGoal) -> Bool {
        // The goal list uses the same calculator as the goal card/detail screens.
        let result = FinancialCalculator.evaluate(
            FinancialInputs(
                savingsMinor: profile.currentSavingsMinor,
                incomeMinor: profile.monthlyIncomeMinor,
                expensesMinor: profile.recurringExpensesMinor,
                targetMinor: goal.targetAmountMinor,
                evaluationDate: today,
                targetDate: goal.targetDate
            )
        )
        switch result.status {
        case .fundedNow, .onTrack:
            return true
        default:
            return false
        }
    }
}
