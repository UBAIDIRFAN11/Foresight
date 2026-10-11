import SwiftUI
import SwiftData

struct SimulatorView: View {
    @Bindable var profile: FinancialProfile
    let initialGoalID: UUID?
    let prefill: SimulatorPrefill?
    let onPrefillConsumed: (UUID) -> Void
    // MainTabView uses this callback to switch to History after a successful save.
    let onSaved: (SavedDecision) -> Void

    @Query private var goals: [FinancialGoal]
    @State private var selectedGoalID: UUID?
    @State private var purchaseName = ""
    @State private var amount = ""
    @State private var errorMessage: String?
    // The current unsaved calculation result, if the user has calculated one.
    @State private var evaluation: PurchaseImpactEvaluation?
    @State private var isShowingResult = false
    @State private var pendingPrefill: SimulatorPrefill?
    @State private var isConfirmingDraftReplacement = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    init(
        profile: FinancialProfile,
        initialGoalID: UUID? = nil,
        prefill: SimulatorPrefill? = nil,
        onPrefillConsumed: @escaping (UUID) -> Void = { _ in },
        onSaved: @escaping (SavedDecision) -> Void = { _ in }
    ) {
        self.profile = profile
        self.initialGoalID = initialGoalID
        self.prefill = prefill
        self.onPrefillConsumed = onPrefillConsumed
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
                    // Goal selection is kept stable even if goals are added or deleted.
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
                // Check freshness right before presenting/saving the result.
                let stale = staleState(for: evaluation)
                PurchaseImpactView(
                    evaluation: evaluation,
                    mode: .live(isStale: stale.isStale, staleMessage: stale.message),
                    onSaved: { decision in
                        onSaved(decision)
                    },
                    onAmountChange: { newAmountMinor in
                        updateLiveEvaluationAmount(newAmountMinor)
                    },
                    onAdjust: {
                        isShowingResult = false
                    },
                    onReevaluate: nil
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
            receivePrefillIfNeeded(prefill)
        }
        .onChange(of: goals.map(\.id)) { _, _ in
            reconcileSelection(preferredID: selectedGoalID)
        }
        .onChange(of: prefill?.token) { _, _ in
            receivePrefillIfNeeded(prefill)
        }
        .confirmationDialog("Replace current simulator draft?", isPresented: $isConfirmingDraftReplacement, titleVisibility: .visible) {
            Button("Replace Draft") {
                if let pendingPrefill {
                    applyPrefill(pendingPrefill)
                }
            }
            Button("Keep Draft", role: .cancel) {
                if let token = pendingPrefill?.token {
                    onPrefillConsumed(token)
                }
                pendingPrefill = nil
            }
        } message: {
            Text("Re-evaluating a saved decision will replace the current unsaved simulator fields.")
        }
    }

    private var sortedGoals: [FinancialGoal] {
        goals.sorted(by: goalSort)
    }

    private var previewAmount: Int64? {
        // A valid amount gets previewed before calculation; invalid text simply
        // waits for the Calculate button to show a validation message.
        try? MoneyFormatting.parseMinorUnits(amount, currency: CurrencyDefinition.definition(for: profile.preferredCurrencyCode))
    }

    private var selectedGoal: FinancialGoal? {
        sortedGoals.first { $0.id == selectedGoalID }
    }

    private func reconcileSelection(preferredID: UUID?) {
        // Preserve a valid selection. Otherwise choose the first sorted goal.
        let ids = Set(sortedGoals.map(\.id))
        if let preferredID, ids.contains(preferredID) {
            selectedGoalID = preferredID
        } else if let selectedGoalID, ids.contains(selectedGoalID) {
            return
        } else {
            selectedGoalID = sortedGoals.first?.id
        }
    }

    private func receivePrefillIfNeeded(_ prefill: SimulatorPrefill?) {
        guard let prefill else { return }
        if hasUnsavedDraft {
            pendingPrefill = prefill
            isConfirmingDraftReplacement = true
        } else {
            applyPrefill(prefill)
        }
    }

    private var hasUnsavedDraft: Bool {
        !FinancialFormValidation.cleanName(purchaseName).isEmpty ||
        !amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        evaluation != nil
    }

    private func applyPrefill(_ prefill: SimulatorPrefill) {
        purchaseName = prefill.purchaseName
        if prefill.currencyCode == profile.preferredCurrencyCode {
            amount = MoneyFormatting.editableText(prefill.amountMinor, currencyCode: prefill.currencyCode)
        } else {
            amount = ""
            errorMessage = "The original decision used \(prefill.currencyCode). Enter an amount in \(profile.preferredCurrencyCode) to re-evaluate with your current profile."
        }
        reconcileSelection(preferredID: prefill.preferredGoalID)
        if selectedGoalID != prefill.preferredGoalID {
            errorMessage = "The original goal is no longer available. Choose a current goal before calculating."
        }
        evaluation = nil
        isShowingResult = false
        pendingPrefill = nil
        onPrefillConsumed(prefill.token)
    }


    private func calculateImpact() {
        focusedField = nil
        // Simulator validates UI input first, then hands clean values to the
        // domain calculator.
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
        // Build a snapshot of the current profile and selected goal values.
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
            // A new calculation gets a new ID so saving it creates a distinct decision.
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
        // The user must recalculate if anything that affected the result changed
        // before the result was saved.
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

    private func updateLiveEvaluationAmount(_ newAmountMinor: Int64) {
        guard let current = evaluation, newAmountMinor != current.purchaseAmountMinor else { return }

        let inputs = FinancialInputs(
            savingsMinor: current.originalSavingsMinor,
            incomeMinor: current.originalIncomeMinor,
            expensesMinor: current.originalExpensesMinor,
            targetMinor: current.goalTargetMinor,
            evaluationDate: current.evaluationDate,
            targetDate: current.goalTargetDate
        )

        switch PurchaseImpactCalculator.evaluate(PurchaseImpactInputs(financialInputs: inputs, purchaseAmountMinor: newAmountMinor)) {
        case .success(let result):
            evaluation = PurchaseImpactEvaluation(
                id: UUID(),
                purchaseName: current.purchaseName,
                purchaseAmountMinor: newAmountMinor,
                currencyCode: current.currencyCode,
                goalID: current.goalID,
                goalName: current.goalName,
                goalTargetMinor: current.goalTargetMinor,
                goalTargetDate: current.goalTargetDate,
                originalSavingsMinor: current.originalSavingsMinor,
                originalIncomeMinor: current.originalIncomeMinor,
                originalExpensesMinor: current.originalExpensesMinor,
                evaluationDate: current.evaluationDate,
                result: result
            )
            amount = MoneyFormatting.editableText(newAmountMinor, currencyCode: current.currencyCode)
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
