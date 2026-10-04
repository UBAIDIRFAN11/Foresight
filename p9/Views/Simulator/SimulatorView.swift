import SwiftUI
import SwiftData

struct SimulatorView: View {
    @Bindable var profile: FinancialProfile
    let initialGoalID: UUID?
    let onSaved: (SavedDecision) -> Void

    @Query private var goals: [FinancialGoal]
    @State private var selectedGoalID: UUID?
    @State private var purchaseName = ""
    @State private var amount = ""
    @State private var errorMessage: String?
    @State private var evaluation: PurchaseImpactEvaluation?
    @State private var isShowingResult = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    init(profile: FinancialProfile, initialGoalID: UUID? = nil, onSaved: @escaping (SavedDecision) -> Void = { _ in }) {
        self.profile = profile
        self.initialGoalID = initialGoalID
        self.onSaved = onSaved
    }

    private enum Field {
        case amount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Simulator")
                        .font(.largeTitle.weight(.bold))
                    Text("Big purchases. Smarter decisions.")
                        .font(.title3)
                }

                if sortedGoals.isEmpty {
                    ContentUnavailableView(
                        "Goal Required",
                        systemImage: "flag",
                        description: Text("Add a savings goal before evaluating a purchase.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Picker("Goal", selection: $selectedGoalID) {
                        ForEach(sortedGoals) { goal in
                            Text(goal.name).tag(Optional(goal.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .foresightCard()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Purchase Details")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Purchase name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Coffee machine", text: $purchaseName)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Amount")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .amount)
                    }
                    Text("Currency: \(profile.preferredCurrencyCode)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foresightCard()

                if let previewAmount {
                    let previewLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: 16))

                    previewLayout {
                        Image(systemName: "creditcard")
                            .font(.largeTitle)
                            .foregroundStyle(ForesightTheme.accent)
                        VStack(alignment: .leading) {
                            Text(MoneyFormatting.display(previewAmount, currencyCode: profile.preferredCurrencyCode))
                                .font(.title.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(profile.preferredCurrencyCode)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(ForesightTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Button {
                    calculateImpact()
                } label: {
                    Label("Calculate Impact", systemImage: "arrow.right.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foresightPrimaryAction()
                .disabled(sortedGoals.isEmpty)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foresightReadableContent()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ForesightTheme.background)
        .navigationDestination(isPresented: $isShowingResult) {
            if let evaluation {
                let stale = staleState(for: evaluation)
                PurchaseImpactView(
                    evaluation: evaluation,
                    mode: .live(isStale: stale.isStale, staleMessage: stale.message),
                    onSaved: { decision in
                        onSaved(decision)
                    },
                    onAdjust: {
                        isShowingResult = false
                    }
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            reconcileSelection(preferredID: initialGoalID)
        }
        .onChange(of: goals.map(\.id)) { _, _ in
            reconcileSelection(preferredID: selectedGoalID)
        }
    }

    private var sortedGoals: [FinancialGoal] {
        goals.sorted(by: goalSort)
    }

    private var previewAmount: Int64? {
        try? MoneyFormatting.parseMinorUnits(amount, currency: CurrencyDefinition.definition(for: profile.preferredCurrencyCode))
    }

    private var selectedGoal: FinancialGoal? {
        sortedGoals.first { $0.id == selectedGoalID }
    }

    private func reconcileSelection(preferredID: UUID?) {
        let ids = Set(sortedGoals.map(\.id))
        if let preferredID, ids.contains(preferredID) {
            selectedGoalID = preferredID
        } else if let selectedGoalID, ids.contains(selectedGoalID) {
            return
        } else {
            selectedGoalID = sortedGoals.first?.id
        }
    }

    private func calculateImpact() {
        focusedField = nil
        let cleanedName = FinancialFormValidation.cleanName(purchaseName)
        guard !cleanedName.isEmpty else {
            errorMessage = "Purchase name is required."
            return
        }
        guard let goal = selectedGoal else {
            errorMessage = "Choose a goal before calculating."
            return
        }

        let currency = CurrencyDefinition.definition(for: profile.preferredCurrencyCode)
        let purchaseMinor: Int64
        do {
            purchaseMinor = try MoneyFormatting.parseMinorUnits(amount, currency: currency)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let evaluationDate = FinancialCalendar.localEvaluationDay()
        let inputs = FinancialInputs(
            savingsMinor: profile.currentSavingsMinor,
            incomeMinor: profile.monthlyIncomeMinor,
            expensesMinor: profile.recurringExpensesMinor,
            targetMinor: goal.targetAmountMinor,
            evaluationDate: evaluationDate,
            targetDate: goal.targetDate
        )

        switch PurchaseImpactCalculator.evaluate(PurchaseImpactInputs(financialInputs: inputs, purchaseAmountMinor: purchaseMinor)) {
        case .success(let result):
            evaluation = PurchaseImpactEvaluation(
                id: UUID(),
                purchaseName: cleanedName,
                purchaseAmountMinor: purchaseMinor,
                currencyCode: profile.preferredCurrencyCode,
                goalID: goal.id,
                goalName: goal.name,
                goalTargetMinor: goal.targetAmountMinor,
                goalTargetDate: goal.targetDate,
                originalSavingsMinor: profile.currentSavingsMinor,
                originalIncomeMinor: profile.monthlyIncomeMinor,
                originalExpensesMinor: profile.recurringExpensesMinor,
                evaluationDate: evaluationDate,
                result: result
            )
            errorMessage = nil
            isShowingResult = true
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func staleState(for evaluation: PurchaseImpactEvaluation) -> (isStale: Bool, message: String?) {
        guard FinancialCalendar.localEvaluationDay() == evaluation.evaluationDate else {
            return (true, "The calendar day has changed since this calculation. Recalculate before saving.")
        }
        guard let goal = sortedGoals.first(where: { $0.id == evaluation.goalID }) else {
            return (true, "The selected goal no longer exists. Recalculate with another goal before saving.")
        }
        if profile.currentSavingsMinor != evaluation.originalSavingsMinor ||
            profile.monthlyIncomeMinor != evaluation.originalIncomeMinor ||
            profile.recurringExpensesMinor != evaluation.originalExpensesMinor ||
            profile.preferredCurrencyCode != evaluation.currencyCode ||
            goal.name != evaluation.goalName ||
            goal.targetAmountMinor != evaluation.goalTargetMinor ||
            goal.targetDate != evaluation.goalTargetDate {
            return (true, "The profile or goal changed since this calculation. Recalculate before saving.")
        }
        return (false, nil)
    }
}
