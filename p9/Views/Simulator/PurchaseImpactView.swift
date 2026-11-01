import SwiftUI
import SwiftData

struct PurchaseImpactView: View {
    // Live results can be saved or adjusted. Saved results are read-only snapshots.
    enum Mode: Equatable {
        case live(isStale: Bool, staleMessage: String?)
        case saved(savedAt: Date)
    }

    let evaluation: PurchaseImpactEvaluation
    let mode: Mode
    let onSaved: ((SavedDecision) -> Void)?
    let onAmountChange: ((Int64) -> Void)?
    let onAdjust: (() -> Void)?
    let onReevaluate: ((SimulatorPrefill) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var reminderCoordinator: ReminderCoordinator
    @AppStorage("remindersPaused") private var remindersPaused = false
    @Query private var reminderRecords: [ReminderRecord]
    @FocusState private var focusedField: Field?
    @State private var savedDecision: SavedDecision?
    @State private var saveError: String?
    @State private var reminderError: String?
    @State private var isShowingReminderSheet = false
    @State private var customReminderDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    
    
    @State private var forecastSession: ForecastSession?
    @State private var insightRequest: FinancialInsightRequest?
    @State private var amountDraft = ""
    @State private var amountError: String?
    @State private var showsAmountRecovery = false
    @State private var amountErrorAttempt = 0
    @State private var saveErrorAttempt = 0
    @AccessibilityFocusState private var amountFocused: Bool
    @AccessibilityFocusState private var forecastFocused: Bool
    @AccessibilityFocusState private var insightFocused: Bool
    @AccessibilityFocusState private var reminderFocused: Bool
    // False once a live save has moved the user to History, so closing the reminder
    // sheet does not send VoiceOver focus back into this now-hidden screen.
    @State private var restoresReminderFocus = true
    @State private var sliderValue = 0.0
    @State private var visibleStartMonth = 0
    @State private var selectedChartDate: Date?

    private enum Field {
        case amount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                consequenceCard
                liveProjectionSection
                if case .live = mode {
                    ForecastCallout(isEnabled: canForecast, accessibilityFocus: $forecastFocused) {
                        forecastSession = ForecastSession(context: ForecastSource.context(evaluation: evaluation))
                    }
                }
                liveAmountControls
                purchaseCard
                goalCard
                impactRows
                if case .live = mode {
                    FinancialInsightButton(title: "Analyse this purchase with AI", isEnabled: liveResultIsCurrent, accessibilityFocus: $insightFocused) {
                        insightRequest = try? FinancialInsightContextBuilder.purchaseRequest(evaluation: evaluation)
                    }
                }

                if case .live(let isStale, let message) = mode, isStale {
                    // Stale live results are still visible, but cannot be saved.
                    Label(message ?? "This result is out of date. Recalculate before saving.", systemImage: "exclamationmark.triangle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ForesightTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let saveError {
                    AccessibleErrorSummary(message: saveError, attempt: saveErrorAttempt)
                }

                if let reminderError {
                    Label(reminderError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(ForesightTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let schedulingError = reminderCoordinator.schedulingError {
                    Text(schedulingError).font(.footnote).foregroundStyle(ForesightTheme.warning)
                    Button("Retry Scheduling") {
                        reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused, requestAuthorizationIfNeeded: true)
                    }
                }
                actions
            }
            .foresightReadableContent()
        }
        .background(ForesightTheme.background)
        .onChange(of: reminderCoordinator.schedulingError) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .navigationTitle("Purchase Impact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            syncAmountDraft(forceDraftUpdate: true)
        }
        .onChange(of: evaluation.id) { _, _ in
            savedDecision = nil
            saveError = nil
            syncAmountDraft()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .amount, newValue != .amount {
                if amountError == nil {
                    syncAmountDraft(forceDraftUpdate: true)
                } else {
                    showsAmountRecovery = true
                    amountErrorAttempt += 1
                }
            }
        }
        .sheet(item: $forecastSession, onDismiss: { forecastFocused = true }) { session in
            ForecastFlowView(session: session, originIsCurrent: canForecast &&
                             session.context.purchase?.evaluationID == evaluation.id)
        }
        .sheet(item: $insightRequest, onDismiss: { insightFocused = true }) { request in
            FinancialInsightsSheet(request: request, sourceIsCurrent: purchaseInsightIsCurrent(request),
                                   validateSource: { try validatePurchaseInsight(request) })
        }
        .sheet(isPresented: $isShowingReminderSheet, onDismiss: { if restoresReminderFocus { reminderFocused = true } }) {
            NavigationStack {
                reminderSetupSheet
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var canForecast: Bool { liveResultIsCurrent }

    // A live result is current when it is not stale and the amount field still matches it.
    private var liveResultIsCurrent: Bool {
        guard case .live(let isStale, _) = mode else { return false }
        return !isStale && amountError == nil && amountDraftMatchesEvaluation
    }

    // A different evaluation ID means the amount was re-evaluated after the request was made.
    private func purchaseInsightIsCurrent(_ request: FinancialInsightRequest) -> Bool {
        guard case .purchase(let snapshot) = request.context else { return false }
        return snapshot.evaluationID == evaluation.id && liveResultIsCurrent
    }

    // Reuses the save-time freshness check; the AI path never saves anything.
    private func validatePurchaseInsight(_ request: FinancialInsightRequest) throws {
        guard case .purchase(let snapshot) = request.context,
              snapshot.evaluationID == evaluation.id else { throw FinancialInsightStaleSourceError() }
        try SavedDecisionStore.validateLive(evaluation, in: modelContext)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(evaluation.purchaseName)
                .accessibilityAddTraits(.isHeader)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Evaluated \(formatted(evaluation.evaluationDate))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .saved(let savedAt) = mode {
                Text("Saved \(savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var consequenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(consequenceTitle, systemImage: consequenceIcon)
                .accessibilityAddTraits(.isHeader)
                .font(.headline)
                .foregroundStyle(consequenceColor)
            Text(consequenceMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foresightCard()
    }

    private var purchaseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Purchase")
                .accessibilityAddTraits(.isHeader)
                .font(.headline)
            if case .saved = mode {
                AdaptiveValueRow(title: "Amount", value: MoneyFormatting.display(evaluation.purchaseAmountMinor, currencyCode: evaluation.currencyCode), spokenValue: AccessibilityMoney.spoken(evaluation.purchaseAmountMinor, currencyCode: evaluation.currencyCode))
            }
            if let conversion = evaluation.conversion {
                ConversionSummary(conversion: conversion, convertedMinor: evaluation.purchaseAmountMinor)
            }
            AdaptiveValueRow(title: "Remaining savings", value: MoneyFormatting.display(evaluation.result.remainingSavingsMinor, currencyCode: evaluation.currencyCode), spokenValue: AccessibilityMoney.spoken(evaluation.result.remainingSavingsMinor, currencyCode: evaluation.currencyCode))
            AdaptiveValueRow(title: "Currency", value: evaluation.currencyCode)
        }
        .foresightCard()
    }

    @ViewBuilder
    private var liveProjectionSection: some View {
        if case .live = mode {
            
            //includes purchase amount, so FinancialProjectionBuilder builds both basline/after purchase trajectories
            let projection = FinancialProjectionBuilder.build(
                inputs: projectionInputs,
                purchaseAmountMinor: evaluation.purchaseAmountMinor,
                visibleStartMonth: visibleStartMonth
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Projection")
                        .accessibilityAddTraits(.isHeader)
                        .font(.headline)
                    Spacer(minLength: 12)
                    Text("Months \(visibleStartMonth)-\(visibleStartMonth + FinancialProjectionBuilder.defaultVisibleMonthCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch projection {
                case .success(let projection):
                    if let explanation = projection.explanation {
                        Text(explanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SavingsProjectionChart(
                        projection: projection,
                        currencyCode: evaluation.currencyCode,
                        selectedDate: $selectedChartDate
                    )
                    timelineControls(for: projection)
                case .failure(let error):
                    Label(error.localizedDescription, systemImage: "chart.xyaxis.line")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foresightCard()
        }
    }

    @ViewBuilder
    private var liveAmountControls: some View {
        if case .live = mode {
            VStack(alignment: .leading, spacing: 12) {
                Text("Adjust Purchase")
                    .accessibilityAddTraits(.isHeader)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Exact amount (\(evaluation.originalCurrencyCode))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("0", text: amountDraftBinding)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .amount)
                        .accessibilityLabel("Exact purchase amount, \(AccessibilityMoney.currencyName(evaluation.originalCurrencyCode))")
                        .accessibilityHint(amountError ?? "Recalculates the impact as you edit.")
                        .accessibilityFocused($amountFocused)
                }

                if canUseSlider {
                    Slider(
                        value: sliderBinding,
                        in: Double(sliderMinimumMinor)...Double(sliderMaximumMinor),
                        step: 1
                    )
                    .accessibilityLabel("Purchase amount")
                    .accessibilityValue(AccessibilityMoney.spoken(Int64(sliderBinding.wrappedValue), currencyCode: evaluation.originalCurrencyCode))
                    .accessibilityHint("Recalculates the purchase impact.")
                    HStack {
                        Text(MoneyFormatting.display(sliderMinimumMinor, currencyCode: evaluation.originalCurrencyCode))
                        Spacer()
                        Text(MoneyFormatting.display(sliderMaximumMinor, currencyCode: evaluation.originalCurrencyCode))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Use the exact amount field for amounts outside the safe slider range.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let amountError {
                    if showsAmountRecovery {
                        AccessibleErrorSummary(message: amountError, fieldName: "Exact purchase amount", attempt: amountErrorAttempt) {
                            showsAmountRecovery = false
                            focusedField = .amount
                            amountFocused = true
                        }
                    } else {
                        // Visible and discoverable during typing, without interrupting it.
                        Label(amountError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(ForesightTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foresightCard()
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Goal")
                .accessibilityAddTraits(.isHeader)
                .font(.headline)
            AdaptiveValueRow(title: "Name", value: evaluation.goalName)
            AdaptiveValueRow(title: "Target", value: MoneyFormatting.display(evaluation.goalTargetMinor, currencyCode: evaluation.currencyCode), spokenValue: AccessibilityMoney.spoken(evaluation.goalTargetMinor, currencyCode: evaluation.currencyCode))
            AdaptiveValueRow(title: "Deadline", value: formatted(evaluation.goalTargetDate))
        }
        .foresightCard()
    }

    private var impactRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Impact")
                .accessibilityAddTraits(.isHeader)
                .font(.headline)
            AdaptiveValueRow(title: "Before purchase", value: completionDateText(evaluation.result.baseline.completionProjection))
            AdaptiveValueRow(title: "After purchase", value: completionDateText(evaluation.result.afterPurchase.completionProjection))
            AdaptiveValueRow(title: "Completion delay", value: metricText(evaluation.result.purchaseDelay))
            AdaptiveValueRow(title: "Extra monthly savings", value: moneyMetricText(evaluation.result.extraMonthlySavings), spokenValue: spokenMetric(evaluation.result.extraMonthlySavings))
            AdaptiveValueRow(title: "Deadline-safe purchase", value: moneyMetricText(evaluation.result.maximumPurchasePreservingDeadline), spokenValue: spokenMetric(evaluation.result.maximumPurchasePreservingDeadline))
            AdaptiveValueRow(title: "Deadline balance before", value: MoneyFormatting.display(evaluation.result.deadlineBalanceBeforeMinor, currencyCode: evaluation.currencyCode), spokenValue: AccessibilityMoney.spoken(evaluation.result.deadlineBalanceBeforeMinor, currencyCode: evaluation.currencyCode))
            AdaptiveValueRow(title: "Deadline balance after", value: MoneyFormatting.display(evaluation.result.deadlineBalanceAfterMinor, currencyCode: evaluation.currencyCode), spokenValue: AccessibilityMoney.spoken(evaluation.result.deadlineBalanceAfterMinor, currencyCode: evaluation.currencyCode))
        }
        .foresightCard()
    }

    @ViewBuilder
    private var actions: some View {
        switch mode {
        case .saved:
            savedActions
        case .live(let isStale, _):
            Button {
                save()
            } label: {
                Label(savedDecision == nil ? "Save Decision" : "Decision Saved", systemImage: savedDecision == nil ? "square.and.arrow.down" : "checkmark.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foresightPrimaryAction()
            .disabled(isStale || savedDecision != nil || amountError != nil || !amountDraftMatchesEvaluation)

            Button {
                do {
                    try SavedDecisionStore.validateLive(evaluation, in: modelContext)
                    saveError = nil
                    restoresReminderFocus = true
                    isShowingReminderSheet = true
                } catch { saveError = error.localizedDescription; saveErrorAttempt += 1 }
            } label: {
                Label("Save & Remind Me", systemImage: "bell.badge")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isStale || amountError != nil || !amountDraftMatchesEvaluation)
            .accessibilityFocused($reminderFocused)

            if isStale {
                Button {
                    onAdjust?()
                } label: {
                    Label("Recalculate Purchase", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var savedActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Reminder")
                    .accessibilityAddTraits(.isHeader)
                    .font(.headline)
                Text(reminderStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    restoresReminderFocus = true
                    isShowingReminderSheet = true
                } label: {
                    Label(activeReminder == nil ? "Set Review Reminder" : "Reschedule Reminder", systemImage: "bell")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityFocused($reminderFocused)

                if let activeReminder {
                    Button(role: .destructive) {
                        cancelReminder(activeReminder)
                    } label: {
                        Label("Cancel Reminder", systemImage: "bell.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        markReviewed(activeReminder)
                    } label: {
                        Label("Mark Reviewed", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .foresightPrimaryAction()
                } else if purchaseReminder?.isReviewed == true {
                    Label("Reviewed. This only records that you reconsidered the purchase; it does not change actual savings.", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(ForesightTheme.success)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foresightCard()

            Button {
                if let decision = currentDecision {
                    onReevaluate?(SimulatorPrefill(decision: decision))
                }
            } label: {
                Label("Re-evaluate With Current Profile", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(currentDecision == nil)
            .accessibilityHint("Loads this purchase into the Simulator using your current profile. You will be asked before replacing an unsaved draft.")
        }
    }

    private var reminderSetupSheet: some View {
        List {
            Section {
                reminderOptionButton("Tomorrow", date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400))
                reminderOptionButton("In 3 Days", date: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date().addingTimeInterval(259_200))
                reminderOptionButton("In 7 Days", date: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(604_800))
            }

            if let reminderError {
                Section { Text(reminderError).foregroundStyle(ForesightTheme.warning) }
            }
            Section("Custom") {
                DatePicker(
                    "Date and Time",
                    selection: $customReminderDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Button {
                    saveReminder(for: customReminderDate)
                } label: {
                    Label("Use Custom Time", systemImage: "calendar.badge.clock")
                }
            }

            if reminderCoordinator.deliverySettings.permissionState == .denied {
                Section {
                    Button("Open iOS Settings") {
                        reminderCoordinator.openSystemSettings()
                    }
                } footer: {
                    Text("The reminder is saved, but iOS notification permission is currently denied.")
                }
            }
        }
        .navigationTitle("Review Reminder")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    isShowingReminderSheet = false
                }
            }
        }
    }

    private func reminderOptionButton(_ title: String, date: Date) -> some View {
        Button {
            saveReminder(for: date)
        } label: {
            Label(title, systemImage: "clock")
        }
    }

    private var consequenceTitle: String {
        // The headline summarizes the main consequence before the detailed rows.
        if evaluation.result.afterPurchase.deadlineBalanceMinor < evaluation.goalTargetMinor {
            return "Deadline Missed"
        }
        if let delay = evaluation.result.purchaseDelay.monthCount, delay > 0 {
            return "Delayed, Still On Track"
        }
        if evaluation.result.purchaseDelay.monthCount == 0 {
            return "No Completion Delay"
        }
        return "Estimate Unavailable"
    }

    private var consequenceMessage: String {
        if evaluation.result.afterPurchase.deadlineBalanceMinor < evaluation.goalTargetMinor {
            return "After this purchase, the projected balance on the deadline is below the target."
        }
        if let delay = evaluation.result.purchaseDelay.monthCount, delay > 0 {
            return "This purchase delays completion by \(delay) \(delay == 1 ? "month" : "months"), but the goal still reaches the target by the deadline."
        }
        if evaluation.result.purchaseDelay.monthCount == 0 {
            return "The goal's estimated completion timing does not change."
        }
        return metricText(evaluation.result.purchaseDelay)
    }

    private var consequenceIcon: String {
        evaluation.result.afterPurchase.deadlineBalanceMinor < evaluation.goalTargetMinor ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var consequenceColor: Color {
        evaluation.result.afterPurchase.deadlineBalanceMinor < evaluation.goalTargetMinor ? ForesightTheme.warning : ForesightTheme.success
    }

    private func save() {
        guard amountError == nil, amountDraftMatchesEvaluation else { return }
        do {
            // SavedDecisionStore handles duplicate prevention and rollback.
            let decision = try SavedDecisionStore.saveLive(evaluation, in: modelContext)
            savedDecision = decision
            saveError = nil
            onSaved?(decision)
        } catch {
            saveError = "Could not save this decision. \(error.localizedDescription)"
            saveErrorAttempt += 1
        }
    }

    @discardableResult
    private func ensureSavedDecision() throws -> SavedDecision {
        if case .live = mode {
            guard amountError == nil, amountDraftMatchesEvaluation else { throw PurchaseImpactError.invalidPurchaseAmount }
            let decision = try SavedDecisionStore.saveLive(evaluation, in: modelContext)
            savedDecision = decision
            return decision
        }
        if let currentDecision {
            savedDecision = currentDecision
            return currentDecision
        }
        let decision = try SavedDecisionStore.save(evaluation, in: modelContext)
        savedDecision = decision
        saveError = nil
        return decision
    }

    private func saveReminder(for date: Date) {
        do {
            let decision: SavedDecision
            if case .live = mode {
                guard amountError == nil, amountDraftMatchesEvaluation else { throw PurchaseImpactError.invalidPurchaseAmount }
                decision = try ReminderStore.saveLivePurchaseReminder(evaluation: evaluation, deliveryDate: date, in: modelContext)
                savedDecision = decision
            } else {
                decision = try ensureSavedDecision()
                _ = try ReminderStore.upsertPurchaseReminder(for: decision, deliveryDate: date, in: modelContext)
            }
            reminderError = nil
            if case .live = mode, onSaved != nil { restoresReminderFocus = false }
            isShowingReminderSheet = false
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused, requestAuthorizationIfNeeded: true)
            if case .live = mode { onSaved?(decision) }
        } catch {
            reminderError = currentDecision == nil ? error.localizedDescription : "Decision saved. Reminder was not saved: \(error.localizedDescription) Retry here; the decision will not be duplicated."
            if let reminderError { AccessibilityNotification.Announcement(reminderError).post() }
        }
    }

    private func cancelReminder(_ reminder: ReminderRecord) {
        do {
            try ReminderStore.cancel(reminder, in: modelContext)
            reminderError = nil
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
        } catch {
            reminderError = error.localizedDescription
            if let reminderError { AccessibilityNotification.Announcement(reminderError).post() }
        }
    }

    private func markReviewed(_ reminder: ReminderRecord) {
        do {
            try ReminderStore.markReviewed(reminder, in: modelContext)
            reminderError = nil
            reminderCoordinator.reconcile(in: modelContext, globallyPaused: remindersPaused)
        } catch {
            reminderError = error.localizedDescription
            if let reminderError { AccessibilityNotification.Announcement(reminderError).post() }
        }
    }

    private var purchaseReminder: ReminderRecord? {
        reminderRecords.first {
            $0.kind == .purchaseReview && $0.sourceID == evaluation.id
        }
    }

    private var activeReminder: ReminderRecord? {
        guard let record = purchaseReminder, record.isEnabled, !record.isReviewed else { return nil }
        return record
    }

    private var reminderStatusText: String {
        if let activeReminder, let date = activeReminder.deliveryDate {
            let status = reminderCoordinator.status(for: activeReminder, globallyPaused: remindersPaused)
            return "\(status) · \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        if purchaseReminder?.isReviewed == true {
            return "Reviewed. No pending reminder."
        }
        return "No review reminder is scheduled."
    }

    private var currentDecision: SavedDecision? {
        let evaluationID = evaluation.id
        return savedDecision ?? (try? modelContext.fetch(FetchDescriptor<SavedDecision>(
            predicate: #Predicate<SavedDecision> { decision in
                decision.evaluationID == evaluationID
            }
        )).first)
    }

    private func completionText(_ projection: GoalCompletionProjection) -> String {
        // Completion text explains finite projections and unavailable cases.
        switch projection {
        case .completedNow:
            "Completed now"
        case .projected(let months, let date):
            "\(months) \(months == 1 ? "month" : "months") · \(formatted(date))"
        case .noPositiveSavingsCapacity:
            "Unavailable: no positive monthly savings capacity"
        case .beyondLimit:
            "Unavailable: beyond the 1,200-month projection limit"
        }
    }

    private func completionDateText(_ projection: GoalCompletionProjection) -> String {
        switch projection {
        case .completedNow:
            "Completed now"
        case .projected(_, let date):
            formatted(date)
        case .noPositiveSavingsCapacity:
            "Unavailable: no positive monthly savings capacity"
        case .beyondLimit:
            "Unavailable: beyond the 1,200-month projection limit"
        }
    }

    private func metricText(_ metric: PurchaseImpactMetric) -> String {
        switch metric {
        case .months(let months):
            "\(months) \(months == 1 ? "month" : "months")"
        case .amount(let amount):
            MoneyFormatting.display(amount, currencyCode: evaluation.currencyCode)
        case .unavailable(let reason):
            unavailableText(reason)
        }
    }

    private func spokenMetric(_ metric: PurchaseImpactMetric) -> String {
        if case .amount(let amount) = metric {
            return AccessibilityMoney.spoken(amount, currencyCode: evaluation.currencyCode)
        }
        return moneyMetricText(metric)
    }

    private func moneyMetricText(_ metric: PurchaseImpactMetric) -> String {
        switch metric {
        case .amount(let amount):
            MoneyFormatting.display(amount, currencyCode: evaluation.currencyCode)
        case .months(let months):
            "\(months) \(months == 1 ? "month" : "months")"
        case .unavailable(let reason):
            unavailableText(reason)
        }
    }

    private func unavailableText(_ reason: PurchaseImpactUnavailableReason) -> String {
        switch reason {
        case .currentPlanAlreadyMissesDeadline:
            "Unavailable: current plan already falls short"
        case .pastDeadline:
            "Unavailable: deadline is in the past"
        case .noDepositsBeforeDeadline:
            "Unavailable: no monthly deposit occurs before the deadline"
        case .noPositiveSavingsCapacity:
            "Unavailable: no positive monthly savings capacity"
        case .projectionBeyondLimit:
            "Unavailable: beyond the 1,200-month projection limit"
        case .arithmeticOverflow:
            "Unavailable: numbers are too large"
        case .notNeeded:
            "Unavailable"
        }
    }

    private func formatted(_ date: Date) -> String {
        FinancialCalendar.displayDate(fromUTCNoon: date)
            .formatted(.dateTime.day().month(.abbreviated).year())
    }

    private var projectionInputs: FinancialInputs {
        FinancialInputs(
            savingsMinor: evaluation.originalSavingsMinor,
            incomeMinor: evaluation.originalIncomeMinor,
            expensesMinor: evaluation.originalExpensesMinor,
            targetMinor: evaluation.goalTargetMinor,
            evaluationDate: evaluation.evaluationDate,
            targetDate: evaluation.goalTargetDate
        )
    }

    private var sliderBounds: ClosedRange<Int64>? {
        CurrencyConversion.sliderBounds(
            from: CurrencyDefinition.definition(for: evaluation.originalCurrencyCode),
            to: CurrencyDefinition.definition(for: evaluation.currencyCode),
            rate: evaluation.conversion?.exchangeRate.rate ?? 1,
            availableSavings: evaluation.originalSavingsMinor
        )
    }

    private var sliderMinimumMinor: Int64 { sliderBounds?.lowerBound ?? 1 }
    private var sliderMaximumMinor: Int64 { sliderBounds?.upperBound ?? 1 }

    private var canUseSlider: Bool {
        guard let bounds = sliderBounds else { return false }
        return bounds.lowerBound < bounds.upperBound &&
            bounds.upperBound <= 9_007_199_254_740_991 &&
            bounds.contains(evaluation.originalAmountMinor)
    }

    private var amountDraftBinding: Binding<String> {
        Binding(
            get: { amountDraft },
            set: { amountDraftChanged($0) }
        )
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { min(max(sliderValue, Double(sliderMinimumMinor)), Double(sliderMaximumMinor)) },
            set: { sliderChanged($0) }
        )
    }

    private var amountDraftMatchesEvaluation: Bool {
        let currency = CurrencyDefinition.definition(for: evaluation.originalCurrencyCode)
        guard let parsed = try? MoneyFormatting.parseMinorUnits(amountDraft, currency: currency),
              (try? evaluation.convertedCost(for: parsed)) != nil else { return false }
        return parsed == evaluation.originalAmountMinor
    }

    private func syncAmountDraft(forceDraftUpdate: Bool = false) {
        // Evaluation updates acknowledge the user's input; only an explicit
        // formatting event should replace the text they are still editing.
        if forceDraftUpdate {
            amountDraft = MoneyFormatting.editableText(evaluation.originalAmountMinor, currencyCode: evaluation.originalCurrencyCode)
            amountError = nil
        }
        if canUseSlider { sliderValue = Double(evaluation.originalAmountMinor) }
    }

    private func amountDraftChanged(_ newValue: String) {
        showsAmountRecovery = false
        amountDraft = newValue
        let currency = CurrencyDefinition.definition(for: evaluation.originalCurrencyCode)
        do {
            let parsed = try MoneyFormatting.parseMinorUnits(newValue, currency: currency)
            _ = try evaluation.convertedCost(for: parsed)
            amountError = nil
            if canUseSlider { sliderValue = Double(parsed) }
            onAmountChange?(parsed)
        } catch {
            amountError = error.localizedDescription
        }
    }

    //user moves the slider --> SwiftUI passes the new pos
    private func sliderChanged(_ newValue: Double) {
        guard canUseSlider, newValue.isFinite else { return }

        //value is kept within allowed purchase range
        let rounded = min(max(newValue.rounded(), Double(sliderMinimumMinor)), Double(sliderMaximumMinor))
        let minorUnits = Int64(rounded)
        amountDraft = MoneyFormatting.editableText(minorUnits, currencyCode: evaluation.originalCurrencyCode)
        sliderValue = rounded
        amountError = nil

        //inform parent that purchase amount has changed. This connects this view back to SimulatorView
        onAmountChange?(minorUnits)
    }

    private func timelineControls(for projection: SavingsProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    visibleStartMonth = max(visibleStartMonth - FinancialProjectionBuilder.defaultVisibleMonthCount, 0)
                    selectedChartDate = nil
                } label: {
                    Image(systemName: "chevron.left.2")
                        .frame(minWidth: 44)
                }
                .accessibilityLabel("Earlier 12-month window")
                .disabled(!projection.canMoveEarlier)

                Spacer(minLength: 12)

                Button {
                    visibleStartMonth = min(
                        visibleStartMonth + FinancialProjectionBuilder.defaultVisibleMonthCount,
                        FinancialCalculator.completionMonthLimit - FinancialProjectionBuilder.defaultVisibleMonthCount
                    )
                    selectedChartDate = nil
                } label: {
                    Image(systemName: "chevron.right.2")
                        .frame(minWidth: 44)
                }
                .accessibilityLabel("Later 12-month window")
                .disabled(!projection.canMoveLater)
            }

            HStack {
                milestoneButtons(for: projection)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func milestoneButtons(for projection: SavingsProjection) -> some View {
        Group {
            Button {
                visibleStartMonth = max(FinancialCalendar.monthsWithDeposits(from: evaluation.evaluationDate, through: projection.deadlineDate) - 2, 0)
                selectedChartDate = projection.deadlineDate
            } label: {
                Label("Deadline", systemImage: "calendar")
            }
            .accessibilityLabel("Jump to deadline")
            .disabled(FinancialCalendar.isBeforeDay(projection.deadlineDate, evaluation.evaluationDate))

            Spacer(minLength: 12)

            Button {
                if let startMonth = FinancialProjectionBuilder.startMonthForMilestone(projection.afterPurchaseCompletionMonth ?? projection.baselineCompletionMonth) {
                    visibleStartMonth = startMonth
                    selectedChartDate = completionDate(from: projection.afterPurchaseResult?.completionProjection ?? projection.baselineResult.completionProjection)
                }
            } label: {
                Label("Completion", systemImage: "flag.checkered")
            }
            .accessibilityLabel("Jump to completion")
            .disabled(FinancialProjectionBuilder.startMonthForMilestone(projection.afterPurchaseCompletionMonth ?? projection.baselineCompletionMonth) == nil)
        }
    }

    private func completionDate(from projection: GoalCompletionProjection) -> Date? {
        if case .projected(_, let date) = projection {
            return date
        }
        if case .completedNow = projection {
            return evaluation.evaluationDate
        }
        return nil
    }
}

private struct ConversionSummary: View {
    let conversion: PurchaseConversion
    let convertedMinor: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveValueRow(title: "Original price", value: MoneyFormatting.display(conversion.originalAmountMinor, currencyCode: conversion.exchangeRate.base, includeCode: true), spokenValue: AccessibilityMoney.spoken(conversion.originalAmountMinor, currencyCode: conversion.exchangeRate.base))
            AdaptiveValueRow(title: "Converted cost", value: MoneyFormatting.display(convertedMinor, currencyCode: conversion.exchangeRate.quote, includeCode: true), spokenValue: AccessibilityMoney.spoken(convertedMinor, currencyCode: conversion.exchangeRate.quote))
            Text("1 \(conversion.exchangeRate.base) = \(conversion.exchangeRate.rateString) \(conversion.exchangeRate.quote)")
                .font(.footnote)
            Text("Dated exchange-rate information · \(FinancialCalendar.displayDate(fromUTCNoon: conversion.exchangeRate.observationDate).formatted(date: .abbreviated, time: .omitted))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
