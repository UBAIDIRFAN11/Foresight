import SwiftUI
import SwiftData

//disp all saved goals and enables users to filter or add more

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
    @State private var addGoalLauncher: AddGoalLauncher = .toolbar
    @AccessibilityFocusState private var focusedLauncher: AddGoalLauncher?
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

                    if let emptyState = GoalsEmptyState(totalGoalCount: goals.count, filter: filter, matchingCount: displayedGoals.count) {
                        emptyStateView(emptyState)
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
                    addGoal(from: .toolbar)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Goal")
                .accessibilityFocused($focusedLauncher, equals: .toolbar)
            }
        }
        .sheet(isPresented: $isAddingGoal, onDismiss: restoreAddGoalFocus) {
            NavigationStack {
                GoalEditorView(profile: profile, goal: nil, evaluationDay: evaluationDay)
            }
        }
        .navigationDestination(for: UUID.self) { id in
            GoalDetailView(goalID: id, profile: profile, evaluationDay: evaluationDay)
        }
    }

    @ViewBuilder
    private func emptyStateView(_ state: GoalsEmptyState) -> some View {
        switch state {
        case .noGoals:
            ContentUnavailableView {
                Label("No Goals Yet", systemImage: "flag")
            } description: {
                Text("Add your first savings goal to see whether your monthly capacity can reach it on time.")
            } actions: {
                Button("Add Goal") { addGoal(from: .emptyState) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityFocused($focusedLauncher, equals: .emptyState)
            }
        case .noMatches(let emptyFilter):
            ContentUnavailableView {
                Label("No Goals \(emptyFilter.rawValue)", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("None of your \(goals.count) \(goals.count == 1 ? "goal is" : "goals are") \(emptyFilter.rawValue.lowercased()) right now. Show all goals to see them.")
            } actions: {
                // Only the filter changes; goals, statuses and sorting are untouched.
                Button("Show All Goals") { filter = .all }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func addGoal(from launcher: AddGoalLauncher) {
        addGoalLauncher = launcher
        isAddingGoal = true
    }

    private func restoreAddGoalFocus() {
        // The empty-state button disappears once a goal exists, so fall back to the toolbar button.
        if addGoalLauncher == .emptyState, goals.isEmpty {
            focusedLauncher = .emptyState
        } else {
            focusedLauncher = .toolbar
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

private enum AddGoalLauncher: Hashable {
    case toolbar
    case emptyState
}

/// Distinguishes "no goals exist" from "the selected filter has no matches" so the
/// Goals screen can explain the situation and offer the right recovery action.
enum GoalsEmptyState: Equatable {
    case noGoals
    case noMatches(GoalsView.GoalFilter)

    init?(totalGoalCount: Int, filter: GoalsView.GoalFilter, matchingCount: Int) {
        guard matchingCount == 0 else { return nil }
        if totalGoalCount == 0 || filter == .all {
            self = .noGoals
        } else {
            self = .noMatches(filter)
        }
    }
}
