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
    private let today = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Picker("Filter", selection: $filter) {
                    ForEach(GoalFilter.allCases) { option in
                        Text("\(option.rawValue) (\(count(for: option)))").tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if filteredGoals.isEmpty {
                    ContentUnavailableView("No Goals", systemImage: "flag", description: Text("Add a goal to start planning against your monthly capacity."))
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(filteredGoals) { goal in
                            NavigationLink(value: goal.id) {
                                GoalCard(goal: goal, profile: profile, today: today)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
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
            }
        }
        .sheet(isPresented: $isAddingGoal) {
            NavigationStack {
                GoalEditorView(profile: profile, goal: nil)
            }
        }
        .navigationDestination(for: UUID.self) { id in
            GoalDetailView(goalID: id, profile: profile)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Goals")
                .font(.largeTitle.weight(.bold))
            Text("Your dreams, your timeline.")
                .font(.title3)
        }
    }

    private var sortedGoals: [FinancialGoal] {
        goals.sorted(by: goalSort)
    }

    private var filteredGoals: [FinancialGoal] {
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
