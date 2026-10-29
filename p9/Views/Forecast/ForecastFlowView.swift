import SwiftUI
import SwiftData

struct ForecastSession: Identifiable {
    let id = UUID()
    let context: ForecastContext
    let seed: UInt64

    init(context: ForecastContext) {
        self.context = context
        var generator = SystemRandomNumberGenerator()
        seed = generator.next()
    }
}

struct ForecastCallout: View {
    let isEnabled: Bool
    var accessibilityFocus: AccessibilityFocusState<Bool>.Binding
    let open: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("Want to see how changes in income or expenses could affect this projection?")
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button("Forecast Uncertainty",
                   systemImage: "chart.xyaxis.line",
                   action: open)
                .foresightPrimaryAction()
                .disabled(!isEnabled)
                .accessibilityFocused(accessibilityFocus)
                .accessibilityHint("Opens assumptions for simulated income and expense variation.")
        }
        .frame(maxWidth: .infinity)
        .foresightCard()
    }
}

struct ForecastFlowView: View {
    let session: ForecastSession
    var originIsCurrent: Bool = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [FinancialProfile]
    @Query private var goals: [FinancialGoal]
    @State private var incomeVariation = 10.0
    @State private var expenseVariation = 15.0
    @State private var request: ForecastRequest?
    @State private var showsResults = false
    @State private var invalidated = false
    @State private var evaluationDay = FinancialCalendar.localEvaluationDay()
    @State private var errorMessage: String?
    @State private var errorAttempt = 0

    private var sourceMatches: Bool {
        guard originIsCurrent,
              let profile = FinancialProfilePolicy.selectedProfile(from: profiles),
              let goal = goals.first(where: { $0.id == session.context.goalID }) else { return false }
        return ForecastSource.context(profile: profile, goal: goal, evaluationDay: evaluationDay,
                                      purchase: session.context.purchase) == session.context
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForecastContextCard(context: session.context)
                    if invalidated || !sourceMatches {
                        staleMessage
                    } else {
                        assumptions
                        if let errorMessage {
                            AccessibleErrorSummary(message: errorMessage, attempt: errorAttempt)
                        }
                        Button("Run Forecast", systemImage: "play.fill", action: run)
                            .foresightPrimaryAction()
                        ForecastDisclaimer()
                    }
                }
                .foresightReadableContent()
            }
            .background(ForesightTheme.background)
            .navigationTitle("Goal Forecast")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(isPresented: $showsResults) {
                if let request {
                    ForecastResultsView(request: request, sourceIsCurrent: sourceMatches && !invalidated,
                                        validateSource: validateSource, done: { dismiss() })
                        .id(request.id)
                }
            }
        }
        .onChange(of: sourceMatches, initial: true) { _, matches in
            if !matches { invalidated = true }
        }
        .onChange(of: invalidated) { _, isInvalid in
            if isInvalid { AccessibilityNotification.Announcement(ForecastError.staleSource.localizedDescription).post() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshSource() }
        }
        .task {
            // Detect a midnight rollover even when the screen stays open.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                refreshSource()
            }
        }
    }

    private var staleMessage: some View {
        Label(ForecastError.staleSource.localizedDescription, systemImage: "exclamationmark.triangle")
            .foresightCard()
    }

    private var assumptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monthly variation").font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForecastVariabilityControl(title: "Income variability", value: $incomeVariation,
                                       expectedMinor: session.context.inputs.incomeMinor, currencyCode: session.context.currencyCode)
            ForecastVariabilityControl(title: "Expense variability", value: $expenseVariation,
                                       expectedMinor: session.context.inputs.expensesMinor, currencyCode: session.context.currencyCode)
            Text("Amounts near your entered income or expenses occur more often. Each percentage sets the maximum variation in either direction. Months vary independently.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .foresightCard()
    }

    private func validateSource() throws {
        guard !invalidated, originIsCurrent else { throw ForecastError.staleSource }
        try ForecastSource.validate(session.context, in: modelContext)
    }

    private func refreshSource() {
        evaluationDay = FinancialCalendar.localEvaluationDay()
        do { try validateSource() } catch { invalidated = true }
    }

    private func run() {
        do {
            try validateSource()
            let next = ForecastRequest(context: session.context, assumptions: ForecastAssumptions(
                incomeVariability: Int(incomeVariation), expenseVariability: Int(expenseVariation), seed: session.seed))
            _ = try ForecastEngine.validate(next)
            errorMessage = nil
            request = next
            showsResults = true
        } catch {
            if error as? ForecastError == .staleSource { invalidated = true }
            else { errorMessage = error.localizedDescription; errorAttempt += 1 }
        }
    }
}

private struct ForecastVariabilityControl: View {
    let title: String
    @Binding var value: Double
    let expectedMinor: Int64
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveValueRow(title: title, value: "\(Int(value))%")
            Slider(value: $value, in: 0...100, step: 1) { Text(title) }
                .accessibilityValue("\(Int(value)) percent")
            if let lower = try? ForecastEngine.scaledAmount(expectedMinor, percent: Int(value), u: -10_000, v: -10_000),
               let upper = try? ForecastEngine.scaledAmount(expectedMinor, percent: Int(value), u: 10_000, v: 10_000) {
                Text("\(MoneyFormatting.display(lower, currencyCode: currencyCode)) to \(MoneyFormatting.display(upper, currencyCode: currencyCode)) per month")
                    .font(.footnote)
            } else {
                Text("This range exceeds the supported amount.").font(.footnote).foregroundStyle(ForesightTheme.warning)
            }
        }
    }
}

struct ForecastContextCard: View {
    let context: ForecastContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(context.goalName).font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            AdaptiveValueRow(title: "Target", value: money(context.inputs.targetMinor), spokenValue: AccessibilityMoney.spoken(context.inputs.targetMinor, currencyCode: context.currencyCode))
            AdaptiveValueRow(title: "Deadline", value: FinancialCalendar.displayDate(fromUTCNoon: context.inputs.targetDate).formatted(date: .abbreviated, time: .omitted))
            AdaptiveValueRow(title: "Current savings", value: money(context.inputs.savingsMinor), spokenValue: AccessibilityMoney.spoken(context.inputs.savingsMinor, currencyCode: context.currencyCode))
            AdaptiveValueRow(title: "Monthly income", value: money(context.inputs.incomeMinor), spokenValue: AccessibilityMoney.spoken(context.inputs.incomeMinor, currencyCode: context.currencyCode))
            AdaptiveValueRow(title: "Monthly expenses", value: money(context.inputs.expensesMinor), spokenValue: AccessibilityMoney.spoken(context.inputs.expensesMinor, currencyCode: context.currencyCode))
            AdaptiveValueRow(title: "Currency", value: context.currencyCode)
            if let purchase = context.purchase {
                Divider()
                Text(purchase.name).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                AdaptiveValueRow(title: "Purchase cost", value: money(purchase.amountMinor), spokenValue: AccessibilityMoney.spoken(purchase.amountMinor, currencyCode: context.currencyCode))
                if let rate = purchase.rateDescription {
                    Text("Original cost: \(MoneyFormatting.display(purchase.originalAmountMinor, currencyCode: purchase.originalCurrencyCode))")
                    Text(rate).font(.footnote).foregroundStyle(.secondary)
                    Text("Uses the exchange rate from your purchase evaluation.").font(.footnote)
                }
            }
        }
        .foresightCard()
    }

    private func money(_ value: Int64) -> String { MoneyFormatting.display(value, currencyCode: context.currencyCode) }
}

struct ForecastDisclaimer: View {
    var body: some View {
        Text("Simulation estimates based on your selected assumptions, not guaranteed predictions or financial advice. Each goal uses your savings independently.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
