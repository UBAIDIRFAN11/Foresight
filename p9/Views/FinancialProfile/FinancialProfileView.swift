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
    @State private var hasLoadedDraft = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var iconWidth = 42
    @FocusState private var focusedField: MoneyField?

    private enum MoneyField {
        case currentSavings
        case monthlyIncome
        case recurringExpenses
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
                        .font(.largeTitle.weight(.bold))
                    Text("Tell us about your finances to calculate your savings capacity. Your data stays on this device.")
                        .foregroundStyle(.secondary)
                }

                Menu {
                    Picker("Preferred Currency", selection: $currencyCode) {
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
                .disabled(isCurrencyLocked)
                .foresightCard()

                moneyField(title: "Current Savings", icon: "banknote", text: $currentSavings)
                moneyField(title: "Monthly Income", icon: "dollarsign.circle", text: $monthlyIncome)
                moneyField(title: "Recurring Expenses", icon: "percent", text: $recurringExpenses)

                savingsSummary

                if isCurrencyLocked {
                    Label("Currency can be changed once all goals are removed.", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ForesightTheme.warning)
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
        .onAppear(perform: loadDraftIfNeeded)
        .onChange(of: currencyCode) { oldValue, newValue in
            guard hasLoadedDraft, oldValue != newValue else { return }
            currentSavings = ""
            monthlyIncome = ""
            recurringExpenses = ""
        }
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
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold))
                    .focused($focusedField, equals: field(for: title))
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
        do {
            // Guard again at save time in case goals appeared while this screen was open.
            if case .editing(let profile) = mode, profile.preferredCurrencyCode != currencyCode, !goals.isEmpty {
                errorMessage = "Remove all goals before changing currency."
                return
            }
            let savings = try MoneyFormatting.parseMinorUnits(currentSavings, currency: selectedCurrency)
            let income = try MoneyFormatting.parseMinorUnits(monthlyIncome, currency: selectedCurrency)
            let expenses = try MoneyFormatting.parseMinorUnits(recurringExpenses, currency: selectedCurrency)

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
