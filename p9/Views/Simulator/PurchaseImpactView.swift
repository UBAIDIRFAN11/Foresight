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

    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedField: Field?
    @State private var savedDecision: SavedDecision?
    @State private var saveError: String?
    @State private var amountDraft = ""
    @State private var amountError: String?
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
                liveAmountControls
                purchaseCard
                goalCard
                impactRows

                if case .live(let isStale, let message) = mode, isStale {
                    // Stale live results are still visible, but cannot be saved.
                    Label(message ?? "This result is out of date. Recalculate before saving.", systemImage: "exclamationmark.triangle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ForesightTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(ForesightTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actions
            }
            .foresightReadableContent()
        }
        .background(ForesightTheme.background)
        .navigationTitle("Purchase Impact")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            syncAmountDraft(forceDraftUpdate: true)
        }
        .onChange(of: evaluation.id) { _, _ in
            savedDecision = nil
            saveError = nil
            syncAmountDraft()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .amount, newValue != .amount, amountError == nil {
                syncAmountDraft(forceDraftUpdate: true)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(evaluation.purchaseName)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Evaluated \(formatted(evaluation.evaluationDate))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .saved(let savedAt) = mode {
                Text("Saved \(formatted(savedAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var consequenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(consequenceTitle, systemImage: consequenceIcon)
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
                .font(.headline)
            if case .saved = mode {
                AdaptiveValueRow(title: "Amount", value: MoneyFormatting.display(evaluation.purchaseAmountMinor, currencyCode: evaluation.currencyCode))
            }
            AdaptiveValueRow(title: "Remaining savings", value: MoneyFormatting.display(evaluation.result.remainingSavingsMinor, currencyCode: evaluation.currencyCode))
            AdaptiveValueRow(title: "Currency", value: evaluation.currencyCode)
        }
        .foresightCard()
    }

    @ViewBuilder
    private var liveProjectionSection: some View {
        if case .live = mode {
            let projection = FinancialProjectionBuilder.build(
                inputs: projectionInputs,
                purchaseAmountMinor: evaluation.purchaseAmountMinor,
                visibleStartMonth: visibleStartMonth
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Projection")
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
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Exact amount")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("0", text: amountDraftBinding)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .amount)
                }

                if canUseSlider {
                    Slider(
                        value: sliderBinding,
                        in: 1...Double(sliderMaximumMinor),
                        step: 1
                    )
                    HStack {
                        Text(MoneyFormatting.display(1, currencyCode: evaluation.currencyCode))
                        Spacer()
                        Text(MoneyFormatting.display(sliderMaximumMinor, currencyCode: evaluation.currencyCode))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Use the exact amount field for very large balances.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let amountError {
                    Label(amountError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(ForesightTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foresightCard()
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Goal")
                .font(.headline)
            AdaptiveValueRow(title: "Name", value: evaluation.goalName)
            AdaptiveValueRow(title: "Target", value: MoneyFormatting.display(evaluation.goalTargetMinor, currencyCode: evaluation.currencyCode))
            AdaptiveValueRow(title: "Deadline", value: formatted(evaluation.goalTargetDate))
        }
        .foresightCard()
    }

    private var impactRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Impact")
                .font(.headline)
            AdaptiveValueRow(title: "Before purchase", value: completionDateText(evaluation.result.baseline.completionProjection))
            AdaptiveValueRow(title: "After purchase", value: completionDateText(evaluation.result.afterPurchase.completionProjection))
            AdaptiveValueRow(title: "Completion delay", value: metricText(evaluation.result.purchaseDelay))
            AdaptiveValueRow(title: "Extra monthly savings", value: moneyMetricText(evaluation.result.extraMonthlySavings))
            AdaptiveValueRow(title: "Deadline-safe purchase", value: moneyMetricText(evaluation.result.maximumPurchasePreservingDeadline))
            AdaptiveValueRow(title: "Deadline balance before", value: MoneyFormatting.display(evaluation.result.deadlineBalanceBeforeMinor, currencyCode: evaluation.currencyCode))
            AdaptiveValueRow(title: "Deadline balance after", value: MoneyFormatting.display(evaluation.result.deadlineBalanceAfterMinor, currencyCode: evaluation.currencyCode))
        }
        .foresightCard()
    }

    @ViewBuilder
    private var actions: some View {
        switch mode {
        case .saved:
            // History/Home presentations are read-only.
            EmptyView()
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
                onAdjust?()
            } label: {
                Label("Adjust Purchase", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
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
            let decision = try SavedDecisionStore.save(evaluation, in: modelContext)
            savedDecision = decision
            saveError = nil
            onSaved?(decision)
        } catch {
            saveError = "Could not save this decision. \(error.localizedDescription)"
        }
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

    private var sliderSafetyMaximum: Int64 {
        9_000_000_000_000_000
    }

    private var sliderMaximumMinor: Int64 {
        min(evaluation.originalSavingsMinor, sliderSafetyMaximum)
    }

    private var canUseSlider: Bool {
        sliderMaximumMinor >= 1
    }

    private var amountDraftBinding: Binding<String> {
        Binding(
            get: { amountDraft },
            set: { amountDraftChanged($0) }
        )
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { min(max(sliderValue, 1), Double(sliderMaximumMinor)) },
            set: { sliderChanged($0) }
        )
    }

    private var amountDraftMatchesEvaluation: Bool {
        let currency = CurrencyDefinition.definition(for: evaluation.currencyCode)
        guard let parsed = try? MoneyFormatting.parseMinorUnits(amountDraft, currency: currency),
              parsed > 0,
              parsed <= evaluation.originalSavingsMinor else { return false }
        return parsed == evaluation.purchaseAmountMinor
    }

    private func syncAmountDraft(forceDraftUpdate: Bool = false) {
        // Evaluation updates acknowledge the user's input; only an explicit
        // formatting event should replace the text they are still editing.
        if forceDraftUpdate {
            amountDraft = MoneyFormatting.editableText(evaluation.purchaseAmountMinor, currencyCode: evaluation.currencyCode)
            amountError = nil
        }
        sliderValue = Double(min(evaluation.purchaseAmountMinor, sliderMaximumMinor))
    }

    private func amountDraftChanged(_ newValue: String) {
        amountDraft = newValue
        let currency = CurrencyDefinition.definition(for: evaluation.currencyCode)
        do {
            let parsed = try MoneyFormatting.parseMinorUnits(newValue, currency: currency)
            guard parsed > 0 else {
                amountError = "Purchase amount must be greater than zero."
                return
            }
            guard parsed <= evaluation.originalSavingsMinor else {
                amountError = "This purchase is higher than your current savings."
                return
            }
            amountError = nil
            if parsed <= sliderMaximumMinor {
                sliderValue = Double(parsed)
            }
            onAmountChange?(parsed)
        } catch {
            amountError = error.localizedDescription
        }
    }

    private func sliderChanged(_ newValue: Double) {
        let rounded = min(max(newValue.rounded(), 1), Double(sliderMaximumMinor))
        let minorUnits = Int64(rounded)
        amountDraft = MoneyFormatting.editableText(minorUnits, currencyCode: evaluation.currencyCode)
        sliderValue = rounded
        amountError = nil
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
