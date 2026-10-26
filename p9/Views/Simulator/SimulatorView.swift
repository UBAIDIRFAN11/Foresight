import SwiftUI
import SwiftData

struct SimulatorView: View {
    @Bindable var profile: FinancialProfile
    let evaluationDay: Date
    let initialGoalID: UUID?
    let goalSelectionRequestID: UUID?
    let prefill: SimulatorPrefill?
    let onPrefillConsumed: (UUID) -> Void
    // MainTabView uses this callback to switch to History after a successful save.
    let onSaved: (SavedDecision) -> Void

    @Query private var goals: [FinancialGoal]
    @State private var selectedGoalID: UUID?
    @State private var hasInitializedSelection = false
    @State private var purchaseName = ""
    @State private var amount = ""
    
    //store selected currency and request state
    @State private var purchaseCurrencyCode: String
    @State private var lookupTask: Task<Void, Never>?
    @State private var requestID: UUID?
    @State private var isLoadingRate = false
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
        evaluationDay: Date,
        initialGoalID: UUID? = nil,
        goalSelectionRequestID: UUID? = nil,
        prefill: SimulatorPrefill? = nil,
        onPrefillConsumed: @escaping (UUID) -> Void = { _ in },
        onSaved: @escaping (SavedDecision) -> Void = { _ in }
    ) {
        self.evaluationDay = evaluationDay
        self.profile = profile
        _purchaseCurrencyCode = State(initialValue: profile.preferredCurrencyCode)
        self.initialGoalID = initialGoalID
        self.goalSelectionRequestID = goalSelectionRequestID
        self.prefill = prefill
        self.onPrefillConsumed = onPrefillConsumed
        self.onSaved = onSaved
    }

    private enum Field {
        case purchaseName
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
                        Text("Choose a goal").tag(nil as UUID?)
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
                            .focused($focusedField, equals: .purchaseName)
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
                    
                    //disp currency picker
                    Picker("Purchase currency", selection: Binding(
                        get: { purchaseCurrencyCode },
                        set: { currency in
                            cancelLookup()
                            purchaseCurrencyCode = currency
                            amount = ""
                            evaluation = nil
                            errorMessage = nil
                        }
                    )) {
                        ForEach(CurrencyDefinition.supported) { currency in
                            Text("\(currency.code) – \(currency.name)").tag(currency.code)
                        }
                    }
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
                            Text(MoneyFormatting.display(previewAmount, currencyCode: purchaseCurrencyCode))
                                .font(.title.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(purchaseCurrencyCode)
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

                if isLoadingRate {
                    ProgressView("Looking up dated exchange-rate information…")
                    Button("Cancel Lookup", action: cancelLookup)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry", action: calculateImpact)
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
            if !hasInitializedSelection {
                hasInitializedSelection = true
                reconcileSelection(preferredID: initialGoalID)
            }
            receivePrefillIfNeeded(prefill)
        }
        .onChange(of: goalSelectionRequestID) { _, _ in
            reconcileSelection(preferredID: initialGoalID)
        }
        .onChange(of: evaluationDay) { _, _ in cancelLookup() }
        .onChange(of: profile.preferredCurrencyCode) { _, _ in cancelLookup() }
        .onChange(of: financialDraftInputs) { _, _ in cancelLookup() }
        .onChange(of: selectedGoal?.name) { _, _ in cancelLookup() }
        .onChange(of: amount) { _, _ in cancelLookup() }
        .onChange(of: purchaseName) { _, _ in cancelLookup() }
        .onChange(of: selectedGoalID) { _, _ in cancelLookup() }
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
        try? MoneyFormatting.parseMinorUnits(amount, currency: CurrencyDefinition.definition(for: purchaseCurrencyCode))
    }

    private var financialDraftInputs: FinancialInputs? {
        guard let goal = selectedGoal else { return nil }
        return FinancialInputs(savingsMinor: profile.currentSavingsMinor, incomeMinor: profile.monthlyIncomeMinor,
                               expensesMinor: profile.recurringExpensesMinor, targetMinor: goal.targetAmountMinor,
                               evaluationDate: evaluationDay, targetDate: goal.targetDate)
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
            if isShowingResult {
                // The confirmation belongs to the draft screen. Its onAppear
                // presents it after returning from the existing result.
                isShowingResult = false
                return
            }
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
        cancelLookup()
        purchaseCurrencyCode = prefill.currencyCode
        amount = MoneyFormatting.editableText(prefill.amountMinor, currencyCode: prefill.currencyCode)
        errorMessage = nil
        reconcileSelection(preferredID: prefill.preferredGoalID)
        if selectedGoalID != prefill.preferredGoalID {
            selectedGoalID = nil
            errorMessage = "The original goal is no longer available. Choose a current goal before calculating."
        }
        evaluation = nil
        isShowingResult = false
        pendingPrefill = nil
        onPrefillConsumed(prefill.token)
    }


    private func cancelLookup() {
        lookupTask?.cancel()
        lookupTask = nil
        requestID = nil
        isLoadingRate = false
    }

    private func calculateImpact() {
        focusedField = nil
        cancelLookup()
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

        let currency = CurrencyDefinition.definition(for: purchaseCurrencyCode)
        let originalMinor: Int64
        do {
            originalMinor = try MoneyFormatting.parseMinorUnits(amount, currency: currency)
            guard originalMinor > 0 else { throw PurchaseImpactError.invalidPurchaseAmount }
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
        let goalID = goal.id, goalName = goal.name
        
        //define which currencies to convert between
        let sourceCurrency = purchaseCurrencyCode, destinationCurrency = profile.preferredCurrencyCode
        let draftAmount = amount, draftName = purchaseName
        
        //start the async task
        let token = UUID()
        requestID = token
        isLoadingRate = sourceCurrency != destinationCurrency
        errorMessage = nil
        //main actor ensures the state updates inside it happen on the main actor
        lookupTask = Task { @MainActor in
            do {
                
                //fetch exchange rate
                let quote = try await FrankfurterClient().fetchRate(from: sourceCurrency, to: destinationCurrency)
                try Task.checkCancellation()
                guard requestID == token else { return }
                guard amount == draftAmount, purchaseName == draftName, purchaseCurrencyCode == sourceCurrency,
                      selectedGoalID == goalID, let currentGoal = selectedGoal,
                      currentGoal.name == goalName, currentGoal.targetAmountMinor == inputs.targetMinor,
                      currentGoal.targetDate == inputs.targetDate,
                      profile.currentSavingsMinor == inputs.savingsMinor, profile.monthlyIncomeMinor == inputs.incomeMinor,
                      profile.recurringExpensesMinor == inputs.expensesMinor, profile.preferredCurrencyCode == destinationCurrency,
                      FinancialCalendar.localEvaluationDay() == evaluationDate else {
                    throw EvaluationChangedError()
                }
                let converted = try CurrencyConversion.convert(originalMinor,
                    from: CurrencyDefinition.definition(for: sourceCurrency), to: CurrencyDefinition.definition(for: destinationCurrency),
                    rate: quote?.rate ?? 1, availableSavings: inputs.savingsMinor)
                let result = try PurchaseImpactCalculator.evaluate(PurchaseImpactInputs(financialInputs: inputs, purchaseAmountMinor: converted)).get()
                // A new calculation gets a new ID so saving it creates a distinct decision.
                evaluation = PurchaseImpactEvaluation(
                    id: UUID(),
                    purchaseName: cleanedName,
                    purchaseAmountMinor: converted,
                    currencyCode: destinationCurrency,
                    goalID: goalID,
                    goalName: goalName,
                    goalTargetMinor: inputs.targetMinor,
                    goalTargetDate: inputs.targetDate,
                    originalSavingsMinor: inputs.savingsMinor,
                    originalIncomeMinor: inputs.incomeMinor,
                    originalExpensesMinor: inputs.expensesMinor,
                    evaluationDate: evaluationDate,
                    result: result,
                    conversion: quote.map { PurchaseConversion(originalAmountMinor: originalMinor, exchangeRate: $0) }
                )
                isShowingResult = true
            } catch is CancellationError {
                // Superseded requests never replace the current draft or result.
            } catch {
                if requestID == token { errorMessage = error.localizedDescription }
            }
            if requestID == token {
                isLoadingRate = false
                requestID = nil
                lookupTask = nil
            }
        }
    }

    private func staleState(for evaluation: PurchaseImpactEvaluation) -> (isStale: Bool, message: String?) {
        // The user must recalculate if anything that affected the result changed
        // before the result was saved.
        guard evaluationDay == evaluation.evaluationDate else {
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
        guard let current = evaluation else { return }
        do {
            evaluation = try current.adjustingOriginalAmount(newAmountMinor)
            amount = MoneyFormatting.editableText(newAmountMinor, currencyCode: current.originalCurrencyCode)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EvaluationChangedError: LocalizedError {
    var errorDescription: String? { "The draft, profile, goal or calendar day changed during lookup. Calculate again." }
}
