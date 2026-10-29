import SwiftUI
import Charts


struct ForecastChart: View {
    let result: ForecastResult
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var withPurchase = false
    @State private var startMonth = 0
    @State private var selectedDate: Date?


    private var context: ForecastContext { result.request.context }
    private var windowEnd: Date {
        min(context.inputs.targetDate,
            FinancialCalendar.clampedAnniversary(from: context.inputs.evaluationDate, addingMonths: startMonth + 12))
    }
    private var windowStart: Date {
        FinancialCalendar.clampedAnniversary(from: context.inputs.evaluationDate, addingMonths: startMonth)
    }
    private var visibleSamples: [ForecastSample] {
        result.samples.filter { $0.date >= windowStart && $0.date <= windowEnd }
    }
    private var selected: ForecastSample? {
        let visible = visibleSamples
        guard let selectedDate else { return visible.first }
        return visible.min { abs(displayDate($0.date).timeIntervalSince(selectedDate)) < abs(displayDate($1.date).timeIntervalSince(selectedDate)) }
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Range of possible savings").font(.headline)
                .accessibilityAddTraits(.isHeader)
            if context.purchase != nil {
                if dynamicTypeSize.isAccessibilitySize {
                    scenarioPicker.pickerStyle(.menu).controlSize(.large)
                } else {
                    scenarioPicker.pickerStyle(.segmented)
                }
            }
            Text("Middle 80% of simulated outcomes at each month.")
                .font(.footnote)
            chart
            legend
                .font(.caption)
            inspector
            if context.inputs.targetDate > FinancialCalendar.clampedAnniversary(from: context.inputs.evaluationDate, addingMonths: 12) {
                windowControls
            }
        }
        .foresightCard()
    }


    private var scenarioPicker: some View {
        Picker("Inspect scenario", selection: $withPurchase) {
            Text("Baseline").tag(false)
            Text("With Purchase").tag(true)
        }
    }


    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            legendItem("Baseline median", color: ForesightTheme.accent)

            if context.purchase != nil {
                legendItem("With purchase median", color: .blue, dash: [6, 4])
            }

            legendItem("Baseline range", color: ForesightTheme.accent, isArea: true)

            if context.purchase != nil {
                legendItem("Purchase range", color: .blue, isArea: true)
            }

            legendItem("Goal target", color: ForesightTheme.success, dash: [8, 4])

            if context.inputs.targetDate >= windowStart && context.inputs.targetDate <= windowEnd {
                legendItem("Deadline", color: .purple, dash: [2, 5])
            }
        }
    }

    private func legendItem(
        _ title: String,
        color: Color,
        dash: [CGFloat] = [],
        isArea: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Group {
                if isArea {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.23))
                        .frame(width: 32, height: 10)
                } else {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 6))
                        path.addLine(to: CGPoint(x: 32, y: 6))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, dash: dash))
                    .frame(width: 32, height: 12)
                }
            }
            .accessibilityHidden(true)

            Text(title)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }


    private var chart: some View {
        let samples = visibleSamples
        let start = displayDate(windowStart)
        let end = displayDate(windowEnd)
        return Chart {
            ForEach(samples) { sample in
                scenarioMarks(sample: sample, values: sample.baseline, purchase: false)
                if let after = sample.afterPurchase {
                    scenarioMarks(sample: sample, values: after, purchase: true)
                }
            }
            RuleMark(y: .value("Target", amount(context.inputs.targetMinor)))
                .foregroundStyle(ForesightTheme.success)
                .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [8, 4]))
            if context.inputs.targetDate >= windowStart && context.inputs.targetDate <= windowEnd {
                RuleMark(x: .value("Deadline", displayDate(context.inputs.targetDate)))
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [2, 5]))
                    .annotation(position: .top, alignment: .trailing) { Text("Deadline").font(.caption2) }
            }
            if let sample = selected {
                RuleMark(x: .value("Selected date", displayDate(sample.date)))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .chartXScale(domain: start...(end > start ? end : start.addingTimeInterval(86_400)))
        .chartXSelection(value: chartSelection)
        .chartYAxisLabel {
            Text(context.currencyCode).foregroundStyle(Color.secondary)
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 3 : 4)) {
                AxisGridLine()
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.notation(.compactName))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 2 : 4)) {
                AxisGridLine()
                if dynamicTypeSize.isAccessibilitySize {
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                } else {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
        }
        .frame(height: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Simulated savings ranges")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint(context.purchase == nil
            ? "Use Previous Month or Next Month below to inspect exact balances."
            : "Use the scenario selector and Previous Month or Next Month below to inspect exact balances.")
    }


    @ChartContentBuilder
    private func scenarioMarks(sample: ForecastSample, values: ForecastPercentiles, purchase: Bool) -> some ChartContent {
        let name = purchase ? "With Purchase" : "Baseline"
        let color = purchase ? Color.blue : ForesightTheme.accent
        let emphasized = purchase == withPurchase
        AreaMark(x: .value("Date", displayDate(sample.date)),
                 yStart: .value("10th percentile", amount(values.lower)),
                 yEnd: .value("90th percentile", amount(values.upper)),
                 series: .value("Scenario", name))
            .interpolationMethod(.stepEnd)
            .foregroundStyle(color.opacity(emphasized ? 0.23 : 0.08))
        LineMark(x: .value("Date", displayDate(sample.date)), y: .value("Median", amount(values.median)),
                 series: .value("Scenario", name))
            .interpolationMethod(.stepEnd)
            .foregroundStyle(color.opacity(emphasized ? 1 : 0.6))
            .lineStyle(StrokeStyle(lineWidth: emphasized ? 3 : 2, dash: purchase ? [6, 4] : []))
        if visibleSamples.count == 1 {
            PointMark(x: .value("Date", displayDate(sample.date)), y: .value("Median", amount(values.median)))
                .foregroundStyle(color)
                .symbol(purchase ? .square : .circle)
        }
    }


    private var accessibilitySummary: String {
        guard let selected else { return "No month selected." }
        let values = withPurchase ? (selected.afterPurchase ?? selected.baseline) : selected.baseline
        let date = displayDate(selected.date).formatted(date: .abbreviated, time: .omitted)
        return "\(withPurchase ? "With purchase" : "Baseline"), \(date). Lower \(AccessibilityMoney.spoken(values.lower, currencyCode: context.currencyCode)). Median \(AccessibilityMoney.spoken(values.median, currencyCode: context.currencyCode)). Upper \(AccessibilityMoney.spoken(values.upper, currencyCode: context.currencyCode))."
    }

    private var chartSelection: Binding<Date?> {
        Binding(
            get: { selectedDate },
            set: { value in
                // Charts clears its gesture selection on release; keep the snapped
                // month available for reading, matching the deterministic chart.
                guard let value, let sample = visibleSamples.min(by: {
                    abs(displayDate($0.date).timeIntervalSince(value)) <
                    abs(displayDate($1.date).timeIntervalSince(value))
                }) else { return }
                selectedDate = displayDate(sample.date)
            }
        )
    }


    private var inspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected {
                let values = withPurchase ? (selected.afterPurchase ?? selected.baseline) : selected.baseline
                Text("\(withPurchase ? "With Purchase" : "Baseline") · \(displayDate(selected.date).formatted(date: .abbreviated, time: .omitted))")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                AdaptiveValueRow(title: "Lower (10th percentile)", value: money(values.lower), spokenValue: AccessibilityMoney.spoken(values.lower, currencyCode: context.currencyCode))
                AdaptiveValueRow(title: "Median (50th percentile)", value: money(values.median), spokenValue: AccessibilityMoney.spoken(values.median, currencyCode: context.currencyCode))
                AdaptiveValueRow(title: "Upper (90th percentile)", value: money(values.upper), spokenValue: AccessibilityMoney.spoken(values.upper, currencyCode: context.currencyCode))
                ViewThatFits(in: .horizontal) {
                    HStack { previousButton; Spacer(); nextButton }
                    VStack(alignment: .leading) { previousButton; nextButton }
                }
            }
        }
    }


    private var previousButton: some View {
        Button("Previous Month", systemImage: "chevron.left") { moveSelection(-1) }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(selected?.id == result.samples.first?.id)
    }


    private var nextButton: some View {
        Button("Next Month", systemImage: "chevron.right") { moveSelection(1) }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(selected?.id == result.samples.last?.id)
    }


    private var windowControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(displayDate(windowStart).formatted(date: .abbreviated, time: .omitted)) – \(displayDate(windowEnd).formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
            ViewThatFits(in: .horizontal) {
                HStack { earlierButton; laterButton }
                VStack(alignment: .leading) { earlierButton; laterButton }
            }
            Button("Jump to Deadline", systemImage: "calendar") {
                startMonth = max(result.depositMonths - 11, 0)
                selectedDate = displayDate(context.inputs.targetDate)
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
    }


    private var earlierButton: some View {
        Button("Earlier 12 Months") { startMonth = max(startMonth - 12, 0); selectedDate = nil }
            .buttonStyle(.bordered).controlSize(.large).disabled(startMonth == 0)
    }


    private var laterButton: some View {
        Button("Later 12 Months") { startMonth = min(startMonth + 12, result.depositMonths); selectedDate = nil }
            .buttonStyle(.bordered).controlSize(.large).disabled(windowEnd >= context.inputs.targetDate)
    }


    private func moveSelection(_ offset: Int) {
        guard let selected, let index = result.samples.firstIndex(where: { $0.id == selected.id }) else { return }
        let sample = result.samples[min(max(index + offset, 0), result.samples.count - 1)]
        if sample.date < windowStart || sample.date > windowEnd {
            startMonth = max(sample.monthOffset - (offset < 0 ? 11 : 0), 0)
        }
        selectedDate = displayDate(sample.date)
    }


    private func displayDate(_ date: Date) -> Date { FinancialCalendar.displayDate(fromUTCNoon: date) }
    private func money(_ value: Int64) -> String { MoneyFormatting.display(value, currencyCode: context.currencyCode) }
    private func amount(_ value: Int64) -> Double {
        // Double is used only by Charts; all calculations and inspector values stay in minor units.
        Double(value) / pow(10, Double(CurrencyDefinition.definition(for: context.currencyCode).minorUnitScale))
    }
}
