import SwiftUI
import SwiftData

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var profile: FinancialProfile
    let goal: FinancialGoal?

    @State private var name = ""
    @State private var targetAmount = ""
    @State private var targetDate = FinancialCalendar.clampedAnniversary(from: Date(), addingMonths: 6)
    @State private var goalDescription = ""
    @State private var errorMessage: String?
    @State private var loaded = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case targetAmount
    }

    var body: some View {
        // Goal editing uses a native Form so date pickers and text fields behave normally.
        Form {
            Section("Goal") {
                TextField("Name", text: $name)
                LabeledContent("Target amount") {
                    TextField("0", text: $targetAmount)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .targetAmount)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                TextField("Description", text: $goalDescription, axis: .vertical)
                    .lineLimit(3...)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(ForesightTheme.warning)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(ForesightTheme.background)
        .navigationTitle(goal == nil ? "Add Goal" : "Edit Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear(perform: loadDraft)
    }

    private func loadDraft() {
        // Load existing goal values once when editing; new goals keep the defaults.
        guard !loaded else { return }
        loaded = true
        guard let goal else { return }
        name = goal.name
        targetAmount = MoneyFormatting.editableText(goal.targetAmountMinor, currencyCode: profile.preferredCurrencyCode)
        targetDate = FinancialCalendar.displayDate(fromUTCNoon: goal.targetDate)
        goalDescription = goal.goalDescription ?? ""
    }

    private func save() {
        do {
            // Validate and parse before writing anything to SwiftData.
            let cleanedName = FinancialFormValidation.cleanName(name)
            if let message = FinancialFormValidation.validateGoalName(cleanedName) {
                errorMessage = message
                return
            }
            let target = try MoneyFormatting.parseMinorUnits(targetAmount, currency: CurrencyDefinition.definition(for: profile.preferredCurrencyCode))
            if let message = FinancialFormValidation.validateGoalTarget(target) {
                errorMessage = message
                return
            }

            if let goal {
                // Editing mutates the existing SwiftData model.
                goal.name = cleanedName
                goal.targetAmountMinor = target
                goal.targetDate = FinancialCalendar.utcNoon(for: targetDate)
                goal.goalDescription = FinancialFormValidation.optionalDescription(goalDescription)
            } else {
                // Adding inserts a brand-new goal model.
                modelContext.insert(
                    FinancialGoal(
                        name: cleanedName,
                        targetAmountMinor: target,
                        targetDate: targetDate,
                        goalDescription: FinancialFormValidation.optionalDescription(goalDescription)
                    )
                )
            }
            try modelContext.save()
            dismiss()
        } catch {
            // Failed saves should not leave partial draft data in the context.
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
