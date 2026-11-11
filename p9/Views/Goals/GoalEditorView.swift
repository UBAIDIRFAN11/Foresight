import SwiftUI
import SwiftData

//handles creating and editing savings goals

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var profile: FinancialProfile
    let goal: FinancialGoal?
    let evaluationDay: Date

    @State private var priority: GoalPriority = .medium
    @State private var name = ""
    @State private var targetAmount = ""
    @State private var targetDate = Date.distantFuture
    @State private var goalDescription = ""
    @State private var errorMessage: String?
    @State private var failedField: Field?
    @State private var errorAttempt = 0
    @AccessibilityFocusState private var accessibleField: Field?
    @State private var loaded = false
    
    // Values present once the editor finished loading; used to detect unsaved changes.
    @State private var initialDraft: GoalEditorDraft?
    @State private var isConfirmingDiscard = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case targetAmount
        case goalDescription

        var title: String {
            switch self {
            case .name: "Goal name"
            case .targetAmount: "Target amount"
            case .goalDescription: "Description"
            }
        }
    }

    var body: some View {
        // Goal editing uses a native Form so date pickers and text fields behave normally.
        Form {
            Section("Goal") {
                TextField("Name", text: $name)
                    .focused($focusedField, equals: .name)
                    .accessibilityLabel("Goal name")
                    .accessibilityFocused($accessibleField, equals: .name)
                LabeledContent("Target amount") {
                    TextField("0", text: $targetAmount)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .targetAmount)
                        // LabeledContent already supplies "Target amount" to this field.
                        .accessibilityLabel(AccessibilityMoney.currencyName(profile.preferredCurrencyCode))
                        .accessibilityFocused($accessibleField, equals: .targetAmount)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Priority", selection: $priority) {
                    ForEach(GoalPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                TextField("Description", text: $goalDescription, axis: .vertical)
                    .lineLimit(3...)
                    .focused($focusedField, equals: .goalDescription)
            }

            if let errorMessage {
                Section {
                    AccessibleErrorSummary(message: errorMessage, fieldName: failedField?.title, attempt: errorAttempt,
                                           recover: failedField.map { field in
                                               { focusedField = field; accessibleField = field }
                                           })
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
                    // Only ask when leaving would actually lose something the user typed.
                    if hasUnsavedChanges {
                        isConfirmingDiscard = true
                    } else {
                        dismiss()
                    }
                }
                // An alert (not a popover dialog) keeps both choices visible, including Keep Editing.
                .alert("Discard changes?", isPresented: $isConfirmingDiscard) {
                    Button("Discard Changes", role: .destructive) {
                        dismiss()
                    }
                    Button("Keep Editing", role: .cancel) {}
                } message: {
                    Text(goal == nil ? "This goal has not been saved." : "Your edits to this goal have not been saved.")
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
        // A dirty draft can only be closed with Cancel, so swiping down cannot lose it silently.
        .interactiveDismissDisabled(hasUnsavedChanges)
        .onAppear(perform: loadDraft)
    }

    private var currentDraft: GoalEditorDraft {
        GoalEditorDraft(name: name, targetAmountText: targetAmount, targetDate: targetDate,
                        goalDescription: goalDescription, priority: priority)
    }

    private var hasUnsavedChanges: Bool {
        guard let initialDraft else { return false }
        return currentDraft != initialDraft
    }

    private func loadDraft() {
        // Load existing goal values once when editing; new goals keep the defaults.
        guard !loaded else { return }
        loaded = true
        defer { initialDraft = currentDraft }
        guard let goal else {
            targetDate = FinancialCalendar.displayDate(fromUTCNoon: FinancialCalendar.clampedAnniversary(from: evaluationDay, addingMonths: 6))
            return
        }
        priority = goal.priority
        name = goal.name
        targetAmount = MoneyFormatting.editableText(goal.targetAmountMinor, currencyCode: profile.preferredCurrencyCode)
        targetDate = FinancialCalendar.displayDate(fromUTCNoon: goal.targetDate)
        goalDescription = goal.goalDescription ?? ""
    }

    private func save() {
        focusedField = nil
        failedField = .name
        defer { if errorMessage != nil { errorAttempt += 1 } }
        do {
            // Validate and parse before writing anything to SwiftData.
            let cleanedName = FinancialFormValidation.cleanName(name)
            if let message = FinancialFormValidation.validateGoalName(cleanedName) {
                errorMessage = message
                return
            }
            failedField = .targetAmount
            let target = try MoneyFormatting.parseMinorUnits(targetAmount, currency: CurrencyDefinition.definition(for: profile.preferredCurrencyCode))
            if let message = FinancialFormValidation.validateGoalTarget(target) {
                errorMessage = message
                return
            }

            failedField = nil
            if let goal {
                // Editing mutates the existing SwiftData model.
                goal.priority = priority
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
                        goalDescription: FinancialFormValidation.optionalDescription(goalDescription),
                        priority: priority
                    )
                )
            }
            try modelContext.save()
            errorMessage = nil
            dismiss()
        } catch {
            // Failed saves should not leave partial draft data in the context.
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

/// The editable Goal Editor fields, compared with the loaded values to detect unsaved changes.
/// Raw text is compared so partially typed amounts still count as changes; the date is
/// compared by calendar day because that is the precision the goal stores.
struct GoalEditorDraft: Equatable {
    var name: String
    var targetAmountText: String
    var targetDate: Date
    var goalDescription: String
    var priority: GoalPriority

    static func == (lhs: GoalEditorDraft, rhs: GoalEditorDraft) -> Bool {
        lhs.name == rhs.name &&
            lhs.targetAmountText == rhs.targetAmountText &&
            FinancialCalendar.utcNoon(for: lhs.targetDate) == FinancialCalendar.utcNoon(for: rhs.targetDate) &&
            lhs.goalDescription == rhs.goalDescription &&
            lhs.priority == rhs.priority
    }
}
