import SwiftUI

struct ForecastResultsView: View {
    let request: ForecastRequest
    let sourceIsCurrent: Bool
    let validateSource: @MainActor () throws -> Void
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model = ForecastViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !sourceIsCurrent || model.state == .stale {
                    Label(ForecastError.staleSource.localizedDescription, systemImage: "exclamationmark.triangle")
                } else {
                    switch model.state {
                    case .idle, .running:
                        loading
                    case .completed(let result):
                        ForecastSummary(result: result)
                        ForecastChart(result: result)
                        ForecastDisclaimer()
                        Button("Adjust Assumptions") { dismiss() }
                            .buttonStyle(.bordered).controlSize(.large)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                        Button("Adjust Assumptions and Retry") { dismiss() }
                            .buttonStyle(.bordered).controlSize(.large)
                    case .cancelled:
                        Text("Forecast cancelled.")
                        Button("Back to Assumptions") { dismiss() }
                    case .stale:
                        EmptyView()
                    }
                }
            }
            .foresightReadableContent()
        }
        .background(ForesightTheme.background)
        .navigationTitle("Forecast Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) } }
        .task(id: sourceIsCurrent ? request.id : nil) {
            guard sourceIsCurrent else { model.invalidate(); return }
            await model.run(request, validateSource: validateSource)
        }
        .onDisappear { model.cancel() }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Simulating 5,000 possible outcomes…").font(.headline)
                .accessibilityAddTraits(.isHeader)
            let progress = progressValue
            ProgressView(value: Double(progress), total: 100)
                .accessibilityLabel("Forecast progress")
                .accessibilityValue("\(progress) percent")
            Text("\(progress)%").monospacedDigit()
            Button("Cancel", role: .cancel) {
                model.cancel()
                dismiss()
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .foresightCard()
    }

    private var progressValue: Int {
        if case .running(let value) = model.state { value } else { 0 }
    }
}

private struct ForecastSummary: View {
    let result: ForecastResult
    private var context: ForecastContext { result.request.context }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(result.baselinePercentage)%").font(.largeTitle.bold())
                .accessibilityLabel("Baseline estimated success: \(result.baselinePercentage) percent")
                .accessibilityAddTraits(.isHeader)
            Text("Estimated success reaching \(money(context.inputs.targetMinor)) by \(FinancialCalendar.displayDate(fromUTCNoon: context.inputs.targetDate).formatted(date: .abbreviated, time: .omitted))")
                .font(.headline)
            Text(context.goalName).font(.subheadline)
            if let after = result.purchasePercentage, let reduction = result.reductionPercentagePoints {
                AdaptiveValueRow(title: "With purchase", value: "\(after)% estimated success")
                Text("Reduction: \(reduction) percentage points").font(.headline)
            }
            Text("5,000 simulated outcomes")
            Text("Income variability: \(result.request.assumptions.incomeVariability)% · Expense variability: \(result.request.assumptions.expenseVariability)%")
                .font(.footnote)
            Divider()
            Text("If monthly amounts stay unchanged").font(.headline)
                .accessibilityAddTraits(.isHeader)
            AdaptiveValueRow(title: "Baseline deadline balance", value: money(result.deterministicBaselineMinor))
            if let after = result.deterministicPurchaseMinor {
                AdaptiveValueRow(title: "With purchase", value: money(after))
            }
            if result.depositMonths == 0 {
                Text("No monthly deposit occurs before this deadline, so variability has no effect. The outcome depends on starting savings.")
                    .font(.footnote)
            }
        }
        .foresightCard()
    }

    private func money(_ value: Int64) -> String { MoneyFormatting.display(value, currencyCode: context.currencyCode) }
}
