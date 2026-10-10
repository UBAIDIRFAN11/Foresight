import SwiftUI
import SwiftData

struct GoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [FinancialGoal]

    @Bindable var profile: FinancialProfile
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?
    private let today = Date()

    init(goalID: UUID, profile: FinancialProfile) {
        // Query only the selected goal so edits/deletes update this view automatically.
        _goals = Query(filter: #Predicate<FinancialGoal> { goal in
            goal.id == goalID
        })
        self.profile = profile
    }

    var body: some View {
        Group {
            if let goal = goals.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(goal.name)
                            .font(.largeTitle.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        GoalCard(goal: goal, profile: profile, today: today, showsNavigationIndicator: false)
                        detailRows(for: goal)
                        deleteButton
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(ForesightTheme.warning)
                        }
                    }
                    .foresightReadableContent()
                }
                .background(ForesightTheme.background)
                .navigationTitle(goal.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
                .sheet(isPresented: $isEditing) {
                    NavigationStack {
                        GoalEditorView(profile: profile, goal: goal)
                    }
                }
                .confirmationDialog("Delete this goal?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete Goal", role: .destructive) {
                        delete(goal)
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                ScrollView {
                    ContentUnavailableView("Goal Missing", systemImage: "questionmark.folder", description: Text("This goal is no longer available."))
                        .foresightReadableContent()
                }
                .background(ForesightTheme.background)
            }
        }
    }

    private func detailRows(for goal: FinancialGoal) -> some View {
        // Detail rows show the current profile's effect on this goal right now.
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
        return VStack(alignment: .leading, spacing: 12) {
            AdaptiveValueRow(title: "Monthly capacity", value: MoneyFormatting.display(result.monthlyCapacityMinor, currencyCode: profile.preferredCurrencyCode))
            AdaptiveValueRow(title: "Remaining", value: MoneyFormatting.display(result.remainingMinor, currencyCode: profile.preferredCurrencyCode))
            AdaptiveValueRow(title: "Required each month", value: MoneyFormatting.display(result.monthlyRequiredMinor, currencyCode: profile.preferredCurrencyCode))
            AdaptiveValueRow(title: "Deadline balance", value: MoneyFormatting.display(result.deadlineBalanceMinor, currencyCode: profile.preferredCurrencyCode))
            AdaptiveValueRow(title: "Priority", value: goal.priority.title)
        }
        .foresightCard()
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Label("Delete Goal", systemImage: "trash")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func delete(_ goal: FinancialGoal) {
        modelContext.delete(goal)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            // Roll back so a failed delete does not leave the context half-changed.
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
