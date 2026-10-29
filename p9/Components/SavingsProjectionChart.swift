import SwiftUI
import Charts

//this file is responsible for drawing the chart. It draws:
// - an orange solid baseline line: shows trajectory under current circumstances (assume nothing changes)
// - an opt. dashed blue line: shows the impact after a purchase is made
// - a green dashed horizontal line: represents target
// - a vertical dot-dashed line: represents deadline

struct SavingsProjectionChart: View {
    
    //it receives (from FinancialProjectionBuilder):
    let projection: SavingsProjection
    let currencyCode: String //tells it how to format money in the chart
    
    //binding connects selected chart date to parent view's state
    @Binding var selectedDate: Date?

    private var selectedSample: SavingsProjectionSample? {
        guard let selectedDate else {
            return projection.samples.first
        }
        return projection.samples.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(selectedDate)) < abs(rhs.date.timeIntervalSince(selectedDate))
        }
    }

    private var selectedIndex: Int? {
        guard let selectedSample else { return nil }
        return projection.samples.firstIndex(where: { $0.id == selectedSample.id })
    }

    private var baselineLabel: String {
        projection.hasComparison ? "Baseline" : "Balance"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            legend
            Chart {
                //loop through the monthly samples and draw the baseline line
                ForEach(projection.samples) { sample in
                    LineMark(
                        //x,y represents the balance at a particular month
                        x: .value("Month", sample.date),
                        y: .value("Balance", majorUnits(sample.baselineBalanceMinor)),
                        series: .value("Scenario", "Baseline")
                    )
                    .foregroundStyle(ForesightTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.stepEnd)
                }

                if projection.hasComparison {
                    //loop through samples to draw the after purchase line
                    ForEach(projection.samples) { sample in
                        if let afterPurchaseBalanceMinor = sample.afterPurchaseBalanceMinor {
                            LineMark(
                                x: .value("Month", sample.date),
                                y: .value("Balance", majorUnits(afterPurchaseBalanceMinor)),
                                series: .value("Scenario", "After purchase")
                            )
                            .foregroundStyle(Color.blue)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [6, 5]))
                            .interpolationMethod(.stepEnd)
                        }
                    }
                }

                //drawing horizontal target line
                RuleMark(y: .value("Goal target", majorUnits(projection.targetMinor)))
                    .foregroundStyle(ForesightTheme.success.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

                //drawing vertical deadline line (provided it falls withiin the displayed time range)
                if projection.deadlineDate >= (projection.samples.first?.date ?? projection.deadlineDate),
                   projection.deadlineDate <= (projection.samples.last?.date ?? projection.deadlineDate) {
                    RuleMark(x: .value("Deadline", projection.deadlineDate))
                        .foregroundStyle(.gray.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3, 7, 3]))
                }

                if let selectedSample {
                    
                    //highlighting the selected month with a circle
                    PointMark(
                        x: .value("Selected month", selectedSample.date),
                        y: .value("Baseline balance", majorUnits(selectedSample.baselineBalanceMinor))
                    )
                    .foregroundStyle(ForesightTheme.accent)
                    .symbol {
                        Circle()
                            .strokeBorder(ForesightTheme.accent, lineWidth: 2)
                            .background(Circle().fill(ForesightTheme.surface))
                            .frame(width: 11, height: 11)
                    }

                    if let afterPurchaseBalanceMinor = selectedSample.afterPurchaseBalanceMinor {
                        PointMark(
                            x: .value("Selected month", selectedSample.date),
                            y: .value("After-purchase balance", majorUnits(afterPurchaseBalanceMinor))
                        )
                        .foregroundStyle(Color.blue)
                        .symbol {
                            Diamond()
                                .stroke(Color.blue, lineWidth: 2)
                                .background(Diamond().fill(ForesightTheme.surface))
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
            .chartXSelection(value: chartSelection) //enables horizontal selection on the chart
            .chartXScale(domain: chartXDomain)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(axisMoney(number))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
            .frame(height: 260)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(projection.hasComparison ? "Savings projection comparison chart" : "Savings projection chart")
            .accessibilityValue(accessibilitySummary)
            .accessibilityHint("Use Previous month or Next month below to inspect balances.")

            inspector
            navigationControls
        }
        .onAppear {
            if selectedDate == nil {
                selectedDate = projection.samples.first?.date
            }
        }
    }

    private var accessibilitySummary: String {
        guard let sample = selectedSample else { return "No month selected." }
        var summary = "\(formatted(sample.date)). \(baselineLabel) \(AccessibilityMoney.spoken(sample.baselineBalanceMinor, currencyCode: currencyCode))."
        if let after = sample.afterPurchaseBalanceMinor {
            summary += " After purchase \(AccessibilityMoney.spoken(after, currencyCode: currencyCode))."
        }
        return summary
    }

    private var chartXDomain: ClosedRange<Date> {
        let first = projection.samples.first?.date ?? projection.deadlineDate
        let last = projection.samples.last?.date ?? projection.deadlineDate
        return first...last
    }

    //receives the selected date and passes it to nearestSampleDate
    private var chartSelection: Binding<Date?> {
        Binding(
            get: {
                selectedDate
            },
            set: { newValue in
                guard let newValue else { return }
                selectedDate = nearestSampleDate(to: newValue)
            }
        )
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                legendItem(baselineLabel, color: ForesightTheme.accent, dash: [])
                if projection.hasComparison {
                    legendItem("After purchase", color: .blue, dash: [6, 5])
                }
                legendItem("Target", color: ForesightTheme.success.opacity(0.8), dash: [6, 4])
                legendItem("Deadline", color: .gray.opacity(0.75), dash: [2, 3, 7, 3])
            }

            VStack(alignment: .leading, spacing: 8) {
                legendItem(baselineLabel, color: ForesightTheme.accent, dash: [])
                if projection.hasComparison {
                    legendItem("After purchase", color: .blue, dash: [6, 5])
                }
                legendItem("Target", color: ForesightTheme.success.opacity(0.8), dash: [6, 4])
                legendItem("Deadline", color: .gray.opacity(0.75), dash: [2, 3, 7, 3])
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ title: String, color: Color, dash: [CGFloat]) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 6))
                path.addLine(to: CGPoint(x: 30, y: 6))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, dash: dash))
            .frame(width: 32, height: 12)
            .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedSample.map { formatted($0.date) } ?? "No month selected")
                .accessibilityAddTraits(.isHeader)
                .font(.headline)
            if let selectedSample {
                AdaptiveValueRow(
                    title: projection.hasComparison ? "Baseline balance" : "Balance",
                    value: MoneyFormatting.display(selectedSample.baselineBalanceMinor, currencyCode: currencyCode), spokenValue: AccessibilityMoney.spoken(selectedSample.baselineBalanceMinor, currencyCode: currencyCode)
                )
                if let afterPurchaseBalanceMinor = selectedSample.afterPurchaseBalanceMinor {
                    AdaptiveValueRow(
                        title: "After purchase",
                        value: MoneyFormatting.display(afterPurchaseBalanceMinor, currencyCode: currencyCode), spokenValue: AccessibilityMoney.spoken(afterPurchaseBalanceMinor, currencyCode: currencyCode)
                    )
                }
                if selectedSample.isDeadline {
                    Label("Goal deadline", systemImage: "calendar.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(ForesightTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var navigationControls: some View {
        HStack {
            //buttons to move the selected point one sample back or forward
            Button {
                moveSelection(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44)
            }
            .accessibilityLabel("Previous month")
            .disabled((selectedIndex ?? 0) <= 0)

            Spacer(minLength: 12)

            Button {
                moveSelection(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44)
            }
            .accessibilityLabel("Next month")
            .disabled((selectedIndex ?? projection.samples.count - 1) >= projection.samples.count - 1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func moveSelection(by offset: Int) {
        let currentIndex = selectedIndex ?? 0
        let newIndex = min(max(currentIndex + offset, 0), projection.samples.count - 1)
        selectedDate = projection.samples[newIndex].date
    }

    private func nearestSampleDate(to date: Date) -> Date {
        projection.samples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.date ?? date
    }

    private func majorUnits(_ minorUnits: Int64) -> Double {
        let scale = MoneyFormatting.pow10(CurrencyDefinition.definition(for: currencyCode).minorUnitScale)
        return Double(minorUnits) / Double(scale)
    }

    private func axisMoney(_ majorUnits: Double) -> String {
        let currency = CurrencyDefinition.definition(for: currencyCode)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.code
        formatter.locale = Locale(identifier: currency.localeIdentifier)
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: majorUnits)) ?? "\(currency.code) \(Int(majorUnits))"
    }

    private func formatted(_ date: Date) -> String {
        FinancialCalendar.displayDate(fromUTCNoon: date)
            .formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
