import Foundation
import FoundationModels

// Generation boundary. The view model depends on this protocol so tests can inject
// controlled fakes; production uses the on-device system language model.
@MainActor
protocol FinancialInsightGenerating {
    func availability() -> FinancialInsightAvailability
    func generate(for request: FinancialInsightRequest) async throws -> GeneratedFinancialInsight
}

// On-device Foundation Models implementation. It receives copied values only and never
// logs prompts, responses or financial values. Default guardrails are kept.
@MainActor
struct FoundationModelInsightService: FinancialInsightGenerating {
    private let model = SystemLanguageModel.default

    static let instructions = """
    You explain financial results inside Foresight, a personal savings app. Foresight has already \
    calculated every figure and relationship in the prompt, and the user can already see the main result. \
    Your job is to explain what the figures mean together: why the result is what it is, and the \
    trade-off or implication it creates for the user.

    Rules:
    - Quote only figures that appear in the prompt, copied exactly. Never calculate, estimate or invent \
    a new amount, percentage, date or number of months, and write numbers as digits.
    - Do not simply restate the status. Connect the relevant figures to explain cause and consequence.
    - Address the user as "you". Use short, plain sentences.
    - Use conditional language such as "under these assumptions". Never promise an outcome.
    - Do not invent causes such as spending habits, and do not tell the user to buy, not buy, \
    or change their income or spending.
    - The summary and the key consideration must make different points.
    - Choose nextStep only from the next steps listed in the prompt.
    """

    func availability() -> FinancialInsightAvailability {
        switch model.availability {
        case .available:
            // Prompts, fixed text and validation are English.
            return model.supportsLocale(Locale.current) ? .available : .unsupportedLanguage
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .unavailable
        }
    }

    func generate(for request: FinancialInsightRequest) async throws -> GeneratedFinancialInsight {
        // Check immediately before generation, because availability can change while the app runs.
        guard availability() == .available else { throw FinancialInsightFailure.assetsUnavailable }
        // A fresh session per attempt: no transcript carries over between explanations or retries.
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(
                to: Self.prompt(for: request),
                generating: GeneratedFinancialInsight.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 512)
            )
            return response.content
        } catch {
            throw Self.failure(for: error)
        }
    }

    // MARK: - Prompts

    // Hybrid prompt: verified figures and Foresight-calculated relationships, so the model can
    // explain implications in concrete terms without doing any arithmetic itself.
    static func prompt(for request: FinancialInsightRequest) -> String {
        let facts = request.facts.map { "- \($0.label): \($0.value)" }.joined(separator: "\n")
        let relationships = request.relationships.map { "- \($0)" }.joined(separator: "\n")
        let rules = request.rules.map { "- \($0)" }.joined(separator: "\n")
        let steps = request.suggestions.map { "- \($0.step.rawValue): \($0.text)" }.joined(separator: "\n")
        return """
        Explanation for: \(request.title.lowercased())
        Result the user already sees: \(request.status)

        Verified figures:
        \(facts)

        Relationships calculated by Foresight:
        \(relationships)

        Rules:
        \(rules)

        Task: \(request.focus)
        Summary: two or three sentences explaining the cause and the implication, quoting the figures that matter.
        Key consideration: one new sentence that adds a point not already in the summary, about \(request.considerationFocus)

        Next steps (choose the most relevant):
        \(steps)
        """
    }

    // MARK: - Error mapping

    // Normalises framework errors into safe UI states. Cancellation passes through unchanged.
    static func failure(for error: any Error) -> any Error {
        if error is CancellationError { return error }
        if #available(iOS 27.0, *), let mapped = currentFailure(for: error) { return mapped }
        if let mapped = legacyFailure(for: error) { return mapped }
        if error is DecodingError { return FinancialInsightFailure.unusableResponse }
        return FinancialInsightFailure.unexpected
    }

    @available(iOS 27.0, *)
    private static func currentFailure(for error: any Error) -> FinancialInsightFailure? {
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .contextTooLarge
            case .rateLimited, .timeout: return .busy
            case .guardrailViolation: return .guardrailViolation
            case .refusal: return .refused
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide: return .unexpected
            @unknown default: return .unexpected
            }
        }
        if error is LanguageModelSession.Error { return .busy }
        if error is SystemLanguageModel.Error { return .assetsUnavailable }
        return nil
    }

    // iOS 26 reports generation failures through the older GenerationError type.
    @available(iOS, introduced: 26.0, deprecated: 27.0)
    private static func legacyFailure(for error: any Error) -> FinancialInsightFailure? {
        guard let error = error as? LanguageModelSession.GenerationError else { return nil }
        switch error {
        case .exceededContextWindowSize: return .contextTooLarge
        case .assetsUnavailable: return .assetsUnavailable
        case .guardrailViolation: return .guardrailViolation
        case .unsupportedLanguageOrLocale: return .unsupportedLanguage
        case .decodingFailure: return .unusableResponse
        case .rateLimited, .concurrentRequests: return .busy
        case .refusal: return .refused
        case .unsupportedGuide: return .unexpected
        @unknown default: return .unexpected
        }
    }
}
