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
    let onAdjust: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var savedDecision: SavedDecision?
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                consequenceCard
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(evaluation.purchaseName)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(MoneyFormatting.display(evaluation.purchaseAmountMinor, currencyCode: evaluation.currencyCode, includeCode: true)) evaluated \(formatted(evaluation.evaluationDate))")
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
            AdaptiveValueRow(title: "Amount", value: MoneyFormatting.display(evaluation.purchaseAmountMinor, currencyCode: evaluation.currencyCode))
            AdaptiveValueRow(title: "Remaining savings", value: MoneyFormatting.display(evaluation.result.remainingSavingsMinor, currencyCode: evaluation.currencyCode))
            AdaptiveValueRow(title: "Currency", value: evaluation.currencyCode)
        }
        .foresightCard()
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
            AdaptiveValueRow(title: "Before purchase", value: completionText(evaluation.result.baseline.completionProjection))
            AdaptiveValueRow(title: "After purchase", value: completionText(evaluation.result.afterPurchase.completionProjection))
            AdaptiveValueRow(title: "Completion delay", value: metricText(evaluation.result.purchaseDelay))
            AdaptiveValueRow(title: "Extra monthly savings", value: moneyMetricText(evaluation.result.extraMonthlySavings))
            AdaptiveValueRow(title: "Maximum purchase preserving deadline", value: moneyMetricText(evaluation.result.maximumPurchasePreservingDeadline))
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
            .disabled(isStale || savedDecision != nil)

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
}
