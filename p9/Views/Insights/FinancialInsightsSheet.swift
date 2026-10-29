// Shared AI explanation sheet for Goal Detail, live Purchase Impact and completed forecasts.
// The originating screen already shows the figures, so the sheet focuses on the validated
// explanation, its key consideration and a scenario-specific next step.
import SwiftUI

struct FinancialInsightsSheet: View {
    let request: FinancialInsightRequest
    // Live signal from the originating screen, e.g. the evaluation or forecast is still current.
    let sourceIsCurrent: Bool
    // Persisted-source check reused from the originating workflow.
    let validateSource: @MainActor () throws -> Void
    var service: any FinancialInsightGenerating = FoundationModelInsightService()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = FinancialInsightViewModel()
    // Changing this identifier is the only way to start another attempt (Retry / Check Again).
    @State private var attemptID = UUID()

    private var isStale: Bool { model.state == .stale || !sourceIsCurrent }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(request.title)
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                        .fixedSize(horizontal: false, vertical: true)
                    if isStale {
                        staleMessage
                    } else {
                        explanationCard
                        if case .completed(let insight) = model.state {
                            nextStepCard(insight.suggestion)
                        }
                    }
                    disclosure
                }
                .foresightReadableContent()
            }
            .background(ForesightTheme.background)
            .navigationTitle("AI Explanation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: attemptID) {
            guard sourceIsCurrent else { model.invalidate(); return }
            await model.generate(request, attemptID: attemptID, validateSource: checkedSource, service: service)
        }
        .onChange(of: sourceIsCurrent) { _, isCurrent in
            if !isCurrent { model.invalidate() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { recheckSource() }
        }
        .task {
            // Detect a midnight rollover while the sheet stays open.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                recheckSource()
            }
        }
        .onChange(of: model.state) { _, state in
            switch state {
            case .unavailable(let availability):
                AccessibilityNotification.Announcement("\(availability.title). \(availability.message)").post()
            case .failed(let failure):
                AccessibilityNotification.Announcement(failure.message).post()
            case .stale:
                AccessibilityNotification.Announcement(FinancialInsightStaleSourceError().localizedDescription).post()
            default: break
            }
        }
        .onDisappear { model.cancel() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI-generated explanation", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(ForesightTheme.accent)
                .accessibilityAddTraits(.isHeader)
            switch model.state {
            case .idle, .generating:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Generating an explanation on this device…")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            case .completed(let insight):
                Text(insight.summary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key consideration")
                        .accessibilityAddTraits(.isHeader)
                        .font(.subheadline.weight(.semibold))
                    Text(insight.keyConsideration)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            case .unavailable(let availability):
                problem(title: availability.title, message: availability.message,
                        actionTitle: availability.canCheckAgain ? "Check Again" : nil)
            case .failed(let failure):
                problem(title: "Explanation Not Available", message: failure.message,
                        actionTitle: failure.canRetry ? "Try Again" : nil)
            case .cancelled:
                problem(title: "Explanation Cancelled", message: "No explanation was generated.",
                        actionTitle: "Try Again")
            case .stale:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foresightCard()
    }

    private func nextStepCard(_ suggestion: FinancialInsightSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Suggested next step", systemImage: "arrow.forward.circle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            // Foresight-authored text for this scenario, chosen by the model from the permitted options.
            Text(suggestion.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foresightCard()
    }

    private var staleMessage: some View {
        Label(FinancialInsightStaleSourceError().localizedDescription, systemImage: "exclamationmark.triangle")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ForesightTheme.warning)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foresightCard()
    }

    // One concise uncertainty sentence for this context, followed by the fixed disclaimer.
    private var disclosure: some View {
        Text("\(request.uncertaintyNote) AI explanations may be incorrect. For information only, not professional financial advice. Generated on this device.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func problem(title: String, message: String, actionTitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "exclamationmark.triangle")
                .accessibilityAddTraits(.isHeader)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForesightTheme.warning)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(actionTitle) { attemptID = UUID() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Source freshness

    // Translates workflow-specific stale errors into the shared AI wording.
    private func checkedSource() throws {
        guard sourceIsCurrent else { throw FinancialInsightStaleSourceError() }
        do { try validateSource() } catch { throw FinancialInsightStaleSourceError() }
    }

    private func recheckSource() {
        guard model.state != .stale else { return }
        do { try checkedSource() } catch { model.invalidate() }
    }
}
