import SwiftUI
import SwiftData

struct FinancialProfileView: View {
    enum Mode {
        case onboarding
        case editing(FinancialProfile)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [FinancialGoal]

    let mode: Mode
    let onProfileSaved: ((FinancialProfile) -> Void)?

    @State private var currentSavings = ""
    @State private var monthlyIncome = ""
    @State private var recurringExpenses = ""
    @State private var currencyCode = "AUD"
    @State private var errorMessage: String?
    @State private var failedField: MoneyField?
    @State private var errorAttempt = 0
    @AccessibilityFocusState private var accessibleField: MoneyField?
    @State private var hasLoadedDraft = false
    @State private var showsPrivacy = false
    @AccessibilityFocusState private var privacyLinkFocused: Bool
    // A currency change that would clear typed amounts waits here until confirmed.
    @State private var pendingCurrencyChange: CurrencyChangeRequest?
    @State private var currencyContextID = UUID()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var iconWidth = 42
    @FocusState private var focusedField: MoneyField?

    private enum MoneyField {
        case currentSavings
        case monthlyIncome
        case recurringExpenses

        var title: String {
            switch self {
            case .currentSavings: "Current Savings"
            case .monthlyIncome: "Monthly Income"
            case .recurringExpenses: "Recurring Expenses"
            }
        }
    }

    init(mode: Mode, onProfileSaved: ((FinancialProfile) -> Void)? = nil) {
        self.mode = mode
        self.onProfileSaved = onProfileSaved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Financial Profile")
                        .accessibilityAddTraits(.isHeader)
                        .font(.largeTitle.weight(.bold))
                    Text("Tell us about your finances to calculate your savings capacity. Your financial records are stored locally; device backups are managed by iOS.")
                        .foregroundStyle(.secondary)
                    Button("Privacy Policy") { showsPrivacy = true }
                        .accessibilityFocused($privacyLinkFocused)
                }

                Menu {
                    Picker("Preferred Currency", selection: Binding(
                        get: { currencyCode },
                        set: { newValue in requestCurrencyChange(to: newValue) }
                    )) {
                        ForEach(CurrencyDefinition.supported) { currency in
                            Text("\(currency.name) (\(currency.code))").tag(currency.code)
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "globe")
                            .font(.title2)
                            .foregroundStyle(ForesightTheme.accent)
                            .frame(width: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preferred Currency")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(selectedCurrency.name) (\(selectedCurrency.code))")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ForesightTheme.accent)
                    }
                }
                .accessibilityLabel("Preferred currency")
                .accessibilityValue("\(selectedCurrency.name)")
                .accessibilityHint("Changing currency clears the entered amounts.")
                .disabled(isCurrencyLocked)
                .foresightCard()

                moneyField(title: "Current Savings", icon: "banknote", text: $currentSavings)
                moneyField(title: "Monthly Income", icon: "dollarsign.circle", text: $monthlyIncome)
                moneyField(title: "Recurring Expenses", icon: "creditcard", text: $recurringExpenses)

                savingsSummary

                if isCurrencyLocked {
                    Label("Your goals use your profile currency. To prevent existing goal amounts from changing meaning, currency changes are disabled while you have active goals.", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    AccessibleErrorSummary(message: errorMessage, fieldName: failedField?.title, attempt: errorAttempt,
                                           recover: failedField.map { field in
                                               { focusedField = field; accessibleField = field }
                                           })
                }

                Button(action: save) {
                    Text(modeTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foresightPrimaryAction()
            }
            .foresightReadableContent()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ForesightTheme.background)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .sheet(isPresented: $showsPrivacy, onDismiss: { privacyLinkFocused = true }) {
            NavigationStack { PrivacyView() }
        }
        .onAppear(perform: loadDraftIfNeeded)
        .onChange(of: amountFields) { _, _ in currencyContextID = UUID() }
        .onChange(of: currencyCode) { _, _ in currencyContextID = UUID() }
        .onChange(of: isCurrencyLocked) { _, _ in currencyContextID = UUID() }
        .onChange(of: editedProfile?.id) { _, _ in currencyContextID = UUID() }
        .onChange(of: editedProfile?.preferredCurrencyCode) { _, _ in currencyContextID = UUID() }
        .onChange(of: [editedProfile?.currentSavingsMinor, editedProfile?.monthlyIncomeMinor, editedProfile?.recurringExpensesMinor]) { _, _ in
            currencyContextID = UUID()
        }
        .alert("Change currency and clear amounts?", isPresented: isConfirmingCurrencyChange, presenting: pendingCurrencyChange) { request in
            Button("Change Currency & Clear Amounts", role: .destructive) { confirmCurrencyChange(request) }
            Button("Keep Current Currency", role: .cancel) { pendingCurrencyChange = nil }
        } message: { request in
            Text(request.message(draftNote: draftNote))
        }
    }

    private var editedProfile: FinancialProfile? {
        if case .editing(let profile) = mode { return profile }
        return nil
    }

    private var amountFields: [CurrencyAmountField] {
        [CurrencyAmountField(title: MoneyField.currentSavings.title, text: currentSavings),
         CurrencyAmountField(title: MoneyField.monthlyIncome.title, text: monthlyIncome),
         CurrencyAmountField(title: MoneyField.recurringExpenses.title, text: recurringExpenses)]
    }

    private var draftNote: String {
        switch mode {
        case .onboarding: "Nothing is saved until you tap Save Profile."
        case .editing: "Your saved profile does not change until you tap Save Changes."
        }
    }

    private var isConfirmingCurrencyChange: Binding<Bool> {
        Binding(get: { pendingCurrencyChange != nil }, set: { if !$0 { pendingCurrencyChange = nil } })
    }

    private func requestCurrencyChange(to newValue: String) {
        switch CurrencyChangeDecision.evaluate(currentCurrencyCode: currencyCode, requestedCurrencyCode: newValue,
                                               fields: amountFields, isLocked: isCurrencyLocked) {
        case .ignore:
            return
        case .applyImmediately:
            applyCurrencyChange(newValue)
        case .confirm(let request):
            // Nothing changes until the user confirms; the picker keeps showing the current currency.
            focusedField = nil
            var stagedRequest = request
            stagedRequest.contextID = currencyContextID
            pendingCurrencyChange = stagedRequest
        }
    }

    private func confirmCurrencyChange(_ request: CurrencyChangeRequest) {
        pendingCurrencyChange = nil
        // Ignore a confirmation that no longer matches the screen it was asked about.
        guard request.isStillValid(currentCurrencyCode: currencyCode, fields: amountFields, isLocked: isCurrencyLocked,
                                   contextID: currencyContextID) else { return }
        applyCurrencyChange(request.requestedCurrencyCode)
    }

    private func applyCurrencyChange(_ newValue: String) {
        currencyCode = newValue
        // Clear only an explicit currency change, never a loaded profile.
        currentSavings = ""
        monthlyIncome = ""
        recurringExpenses = ""
    }

    private var navigationTitle: String {
        switch mode {
        case .onboarding: "Set Up"
        case .editing: "Financial Profile"
        }
    }

    private var modeTitle: String {
        switch mode {
        case .onboarding: "Save Profile"
        case .editing: "Save Changes"
        }
    }

    private var selectedCurrency: CurrencyDefinition {
        CurrencyDefinition.definition(for: currencyCode)
    }

    private var isCurrencyLocked: Bool {
        // Goals are stored in the selected currency. Lock currency while goals exist
        // so old goal amounts are not silently reinterpreted.
        if case .editing(let profile) = mode, profile.preferredCurrencyCode != currencyCode {
            return !goals.isEmpty
        }
        if case .editing = mode {
            return !goals.isEmpty
        }
        return false
    }

    private var savingsSummary: some View {
        // This live preview helps users see monthly capacity before saving.
        let capacity = parsed(monthlyIncome, fallback: 0) - parsed(recurringExpenses, fallback: 0)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Estimated Monthly Savings")
                .font(.headline)
                .foregroundStyle(ForesightTheme.success)
            ViewThatFits(in: .horizontal) {
                Text("\(MoneyFormatting.display(capacity, currencyCode: currencyCode))/month")
                    .font(.title.weight(.bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(MoneyFormatting.display(capacity, currencyCode: currencyCode))
                        .font(.title.weight(.bold))
                    Text("per month")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("Based on your income and expenses")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated monthly savings")
        .accessibilityValue("\(AccessibilityMoney.spoken(capacity, currencyCode: currencyCode)) per month. Based on your income and expenses.")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(ForesightTheme.savingsSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ForesightTheme.savingsBorder, lineWidth: 1.5)
        }
    }

    private func moneyField(title: String, icon: String, text: Binding<String>) -> some View {
        // Money rows stack vertically at large text sizes.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))

        return layout {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(ForesightTheme.accent)
                .frame(width: iconWidth, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold))
                    .focused($focusedField, equals: field(for: title))
                    .accessibilityLabel("\(title), \(selectedCurrency.name)")
                    .accessibilityFocused($accessibleField, equals: field(for: title))
            }
        }
        .foresightCard()
    }

    private func field(for title: String) -> MoneyField {
        switch title {
        case "Current Savings":
            .currentSavings
        case "Monthly Income":
            .monthlyIncome
        default:
            .recurringExpenses
        }
    }

    private func loadDraftIfNeeded() {
        // Editing loads existing profile values once; onboarding starts empty.
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true
        if case .editing(let profile) = mode {
            currencyCode = profile.preferredCurrencyCode
            currentSavings = MoneyFormatting.editableText(profile.currentSavingsMinor, currencyCode: profile.preferredCurrencyCode)
            monthlyIncome = MoneyFormatting.editableText(profile.monthlyIncomeMinor, currencyCode: profile.preferredCurrencyCode)
            recurringExpenses = MoneyFormatting.editableText(profile.recurringExpensesMinor, currencyCode: profile.preferredCurrencyCode)
        }
    }

    private func parsed(_ text: String, fallback: Int64) -> Int64 {
        // The summary should keep rendering while the user is halfway through typing.
        (try? MoneyFormatting.parseMinorUnits(text, currency: selectedCurrency)) ?? fallback
    }

    private func save() {
        focusedField = nil
        failedField = nil
        defer { if errorMessage != nil { errorAttempt += 1 } }
        do {
            // Guard again at save time in case goals appeared while this screen was open.
            if case .editing(let profile) = mode, profile.preferredCurrencyCode != currencyCode, !goals.isEmpty {
                errorMessage = "Remove all goals before changing currency."
                return
            }
            failedField = .currentSavings
            let savings = try MoneyFormatting.parseMinorUnits(currentSavings, currency: selectedCurrency)
            failedField = .monthlyIncome
            let income = try MoneyFormatting.parseMinorUnits(monthlyIncome, currency: selectedCurrency)
            failedField = .recurringExpenses
            let expenses = try MoneyFormatting.parseMinorUnits(recurringExpenses, currency: selectedCurrency)

            failedField = nil
            errorMessage = nil
            switch mode {
            case .onboarding:
                // Onboarding creates the first profile if one still does not exist.
                let profile = FinancialProfile(
                    currentSavingsMinor: savings,
                    monthlyIncomeMinor: income,
                    recurringExpensesMinor: expenses,
                    preferredCurrencyCode: currencyCode
                )
                let saved = try FinancialProfilePolicy.createProfileIfStillMissing(profile, in: modelContext)
                onProfileSaved?(saved)
            case .editing(let profile):
                // Editing updates the selected profile in place.
                profile.currentSavingsMinor = savings
                profile.monthlyIncomeMinor = income
                profile.recurringExpensesMinor = expenses
                profile.preferredCurrencyCode = currencyCode
                try modelContext.save()
                dismiss()
            }
        } catch {
            // Keep the edit screen open and show the error if saving fails.
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
