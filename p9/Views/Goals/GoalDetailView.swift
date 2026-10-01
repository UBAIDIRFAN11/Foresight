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
                        GoalCard(goal: goal, profile: profile, today: today)
                        detailRows(for: goal)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(ForesightTheme.warning)
                        }
                    }
                    .padding()
                }
                .background(ForesightTheme.background)
                .navigationTitle(goal.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete Goal", systemImage: "trash")
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
                ContentUnavailableView("Goal Missing", systemImage: "questionmark.folder", description: Text("This goal is no longer available."))
                    .background(ForesightTheme.background)
            }
        }
    }

    private func detailRows(for goal: FinancialGoal) -> some View {
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
            detailRow("Monthly capacity", MoneyFormatting.display(result.monthlyCapacityMinor, currencyCode: profile.preferredCurrencyCode))
            detailRow("Remaining", MoneyFormatting.display(result.remainingMinor, currencyCode: profile.preferredCurrencyCode))
            detailRow("Required each month", MoneyFormatting.display(result.monthlyRequiredMinor, currencyCode: profile.preferredCurrencyCode))
            detailRow("Deadline balance", MoneyFormatting.display(result.deadlineBalanceMinor, currencyCode: profile.preferredCurrencyCode))
            detailRow("Priority", goal.priority.title)
        }
        .foresightCard()
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    private func delete(_ goal: FinancialGoal) {
        modelContext.delete(goal)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
