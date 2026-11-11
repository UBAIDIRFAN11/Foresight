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
    @State private var failedField: Field?
    @State private var errorAttempt = 0
    @AccessibilityFocusState private var accessibleField: Field?
    
    
    // The current unsaved calculation result, if the user has calculated one.
    @State private var evaluation: PurchaseImpactEvaluation?
    @State private var isShowingResult = false
    @State private var pendingPrefill: SimulatorPrefill?
    @State private var isConfirmingDraftReplacement = false
    // A currency change that would clear the typed amount waits here until confirmed.
    @State private var pendingCurrencyChange: CurrencyChangeRequest?
    @State private var currencyContextID = UUID()
    @State private var isChoosingGoal = false
    @EnvironmentObject private var router: AppRouter
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
        case goal

        var title: String {
            switch self {
            case .purchaseName: "Purchase name"
            case .amount: "Amount"
            case .goal: "Goal"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Simulator")
                        .accessibilityAddTraits(.isHeader)
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
                    selectedGoalReview
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Purchase Details")
                        .accessibilityAddTraits(.isHeader)
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Purchase name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Coffee machine", text: $purchaseName)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .purchaseName)
                            .accessibilityLabel("Purchase name")
                            .accessibilityFocused($accessibleField, equals: .purchaseName)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Amount")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .amount)
                            .accessibilityLabel("Amount, \(AccessibilityMoney.currencyName(purchaseCurrencyCode))")
                            .accessibilityFocused($accessibleField, equals: .amount)
                    }
                    
                    //disp currency picker
                    Picker("Purchase currency", selection: Binding(
                        get: { purchaseCurrencyCode },
                        set: { currency in requestCurrencyChange(to: currency) }
                    )) {
                        ForEach(CurrencyDefinition.supported) { currency in
                            Text("\(currency.code) – \(currency.name)").tag(currency.code)
                        }
                    }
                    .accessibilityHint("Changing currency clears the purchase amount.")
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Purchase amount")
                    .accessibilityValue(AccessibilityMoney.spoken(previewAmount, currencyCode: purchaseCurrencyCode))
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
                    AccessibleErrorSummary(message: errorMessage, fieldName: failedField?.title, attempt: errorAttempt,
                                           recover: recoveryAction)
                    if failedField == nil {
                        Button("Retry", action: calculateImpact)
                    }
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
        .onChange(of: profile.id) { _, _ in cancelLookup() }
        .onChange(of: [profile.currentSavingsMinor, profile.monthlyIncomeMinor, profile.recurringExpensesMinor]) { _, _ in cancelLookup() }
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
        .onChange(of: pendingCurrencyChange) { _, request in
            if request == nil, let pendingPrefill {
                receivePrefillIfNeeded(pendingPrefill)
            }
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
        .sheet(isPresented: $isChoosingGoal, onDismiss: goalChooserDismissed) {
            NavigationStack {
                GoalSelectionSheet(
                    navigationTitle: "Choose Goal",
                    profile: profile,
                    evaluationDay: evaluationDay,
                    selectedID: selectedGoalID,
                    noneOption: GoalSelectionNoneOption(title: "No goal selected", detail: "Choose a goal before calculating.")
                ) { id in
                    selectedGoalID = id
                    // A chosen goal resolves a "choose a goal" error.
                    if id != nil, failedField == .goal { errorMessage = nil; failedField = nil }
                }
            }
        }
        .alert("Change currency and clear amounts?", isPresented: isConfirmingCurrencyChange, presenting: pendingCurrencyChange) { request in
            Button("Change Currency & Clear Amounts", role: .destructive) { confirmCurrencyChange(request) }
            Button("Keep Current Currency", role: .cancel) { pendingCurrencyChange = nil }
        } message: { request in
            Text(request.message(draftNote: "Any calculated result for this draft is also cleared."))
        }
    }

    // The selected goal, shown with the same card as Home so the right goal is visible
    // before calculating, even when several goals share a name.
    private var selectedGoalReview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Goal")
                .accessibilityAddTraits(.isHeader)
                .font(.headline)
            if let goal = selectedGoal {
                GoalCard(goal: goal, profile: profile, today: evaluationDay, showsNavigationIndicator: false, showsCurrencyCode: true)
                // The purchase currency is chosen separately in Purchase Details.
                Text("Goal amounts are in \(CurrencyDefinition.definition(for: profile.preferredCurrencyCode).displayName).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No goal selected. Choose the goal this purchase should be measured against.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foresightCard()
            }
            Button {
                openGoalChooser()
            } label: {
                Label(selectedGoal == nil ? "Choose Goal" : "Change Goal", systemImage: "flag")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Shows each goal's target and deadline.")
            .accessibilityFocused($accessibleField, equals: .goal)
        }
    }

    private var recoveryAction: (() -> Void)? {
        guard let field = failedField else { return nil }
        guard field == .goal else {
            return { focusedField = field; accessibleField = field }
        }
        // "Edit Goal" opens the chooser; with no goals left there is nothing to choose.
        guard !sortedGoals.isEmpty else { return nil }
        return { openGoalChooser() }
    }

    private func openGoalChooser() {
        guard pendingCurrencyChange == nil, !isConfirmingDraftReplacement, pendingPrefill == nil else { return }
        // Stop a running lookup so it cannot open a result while the chooser is up; the draft is kept.
        focusedField = nil
        cancelLookup()
        isChoosingGoal = true
    }

    private func goalChooserDismissed() {
        if let pendingPrefill {
            receivePrefillIfNeeded(pendingPrefill)
            return
        }
        // Return VoiceOver to the opener only while it still exists on the visible Simulator form.
        if pendingPrefill == nil, !sortedGoals.isEmpty, !isShowingResult, router.selectedTab == .simulator {
            accessibleField = .goal
        }
    }

    private var amountFields: [CurrencyAmountField] {
        [CurrencyAmountField(title: "the purchase amount", text: amount)]
    }

    private var isConfirmingCurrencyChange: Binding<Bool> {
        Binding(
            get: { pendingCurrencyChange != nil },
            set: { if !$0 { pendingCurrencyChange = nil } }
        )
    }

    private func requestCurrencyChange(to currency: String) {
        guard currency != purchaseCurrencyCode, !isChoosingGoal, !isConfirmingDraftReplacement,
              pendingPrefill == nil, pendingCurrencyChange == nil else { return }
        switch CurrencyChangeDecision.evaluate(currentCurrencyCode: purchaseCurrencyCode, requestedCurrencyCode: currency,
                                               fields: amountFields, isLocked: false) {
        case .ignore:
            return
        case .applyImmediately:
            applyCurrencyChange(currency)
        case .confirm(let request):
            // Stop any lookup first so a finishing request cannot open a result behind the alert.
            // Keeping the currency leaves the lookup stopped; the user can calculate again.
            focusedField = nil
            cancelLookup()
            var stagedRequest = request
            stagedRequest.contextID = currencyContextID
            pendingCurrencyChange = stagedRequest
        }
    }

    private func confirmCurrencyChange(_ request: CurrencyChangeRequest) {
        pendingCurrencyChange = nil
        // Ignore a confirmation whose draft changed after it was asked for.
        guard pendingPrefill == nil,
              request.isStillValid(currentCurrencyCode: purchaseCurrencyCode, fields: amountFields, isLocked: false,
                                   contextID: currencyContextID) else { return }
        applyCurrencyChange(request.requestedCurrencyCode)
    }

    private func applyCurrencyChange(_ currency: String) {
        cancelLookup()
        purchaseCurrencyCode = currency
        amount = ""
        evaluation = nil
        errorMessage = nil
    }

    private var sortedGoals: [FinancialGoal] {
        goals.sorted(by: goalSort)
    }

    private var previewAmount: Int64? {
        // A valid amount gets previewed before calculation; invalid text simply
        // waits for the Calculate button to show a validation message.
        
        //takes the amount user entered and converts it to that currency's minor units
        try? MoneyFormatting.parseMinorUnits(amount, currency: CurrencyDefinition.definition(for: purchaseCurrencyCode))
    }

    
    //Prepares the financial information needed for calculations
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
        // A new prefill supersedes any currency intent, but waits for the current
        // chooser/alert to close before entering the existing Replace Draft flow.
        cancelLookup()
        pendingPrefill = prefill
        guard !isChoosingGoal, pendingCurrencyChange == nil else { return }
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
        // Prefill restores currency and amount together, so it bypasses the currency confirmation.
        pendingCurrencyChange = nil
        purchaseName = prefill.purchaseName
        cancelLookup()
        purchaseCurrencyCode = prefill.currencyCode
        amount = MoneyFormatting.editableText(prefill.amountMinor, currencyCode: prefill.currencyCode)
        errorMessage = nil
        reconcileSelection(preferredID: prefill.preferredGoalID)
        if selectedGoalID != prefill.preferredGoalID {
            selectedGoalID = nil
            showError(sortedGoals.isEmpty
                      ? "The original goal is no longer available. Add a goal in the Goals tab before calculating."
                      : "The original goal is no longer available. Choose a current goal before calculating.", field: .goal)
        }
        evaluation = nil
        isShowingResult = false
        pendingPrefill = nil
        onPrefillConsumed(prefill.token)
    }


    private func cancelLookup() {
        // Any input/context change invalidates an earlier currency confirmation,
        // even if the user subsequently restores the same amount and currency.
        currencyContextID = UUID()
        lookupTask?.cancel()
        lookupTask = nil
        requestID = nil
        isLoadingRate = false
    }

    private func showError(_ message: String, field: Field? = nil) {
        failedField = field
        errorMessage = message
        errorAttempt += 1
    }

    
    //this function performs the purchase evaluation
    private func calculateImpact() {
        focusedField = nil
        cancelLookup()
        // Simulator validates UI input first, then hands clean values to the
        // domain calculator.
        let cleanedName = FinancialFormValidation.cleanName(purchaseName)
        guard !cleanedName.isEmpty else {
            showError("Purchase name is required.", field: .purchaseName)
            return
        }
        guard let goal = selectedGoal else {
            showError("Choose a goal before calculating.", field: .goal)
            return
        }

        //convert amount from text into int64 minor units
        let currency = CurrencyDefinition.definition(for: purchaseCurrencyCode)
        let originalMinor: Int64
        do {
            originalMinor = try MoneyFormatting.parseMinorUnits(amount, currency: currency)
            guard originalMinor > 0 else { throw PurchaseImpactError.invalidPurchaseAmount }
        } catch {
            showError(error.localizedDescription, field: .amount)
            return
        }

        //Creates FinancialInputs using the profile's savings, income, expenses and selected goal.
        let evaluationDate = FinancialCalendar.localEvaluationDay()
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
                
                //convert the amount
                let converted = try CurrencyConversion.convert(originalMinor,
                    from: CurrencyDefinition.definition(for: sourceCurrency), to: CurrencyDefinition.definition(for: destinationCurrency),
                    rate: quote?.rate ?? 1, availableSavings: inputs.savingsMinor)
                
                //calculate the impact of the purchase
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
                
                //set to true to disp purchaseimpactview
                isShowingResult = true
            } catch is CancellationError {
                // Superseded requests never replace the current draft or result.
            } catch {
                if requestID == token { showError(error.localizedDescription) }
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
