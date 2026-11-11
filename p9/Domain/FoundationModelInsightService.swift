import Foundation
import FoundationModels

//the purpose of this is to communicate with Apple's on-device language model.
//it's the component that actually generates the AI text

//defines 2 operations that the AI service must support: availability and generating explanation.
@MainActor
protocol FinancialInsightGenerating {
    func availability() -> FinancialInsightAvailability
    func generate(for request: FinancialInsightRequest,
                  sampling: FinancialInsightSampling) async throws -> GeneratedFinancialInsight
}

//implement the protocol using apple's on-device language model
@MainActor
struct FoundationModelInsightService: FinancialInsightGenerating {
    private let model = SystemLanguageModel.default

    //AI instruction prompt
    static let instructions = """
    You explain financial results inside Foresight, a personal savings app. Foresight has already \
    calculated every figure and relationship in the prompt, and the user can already see the main result. \
    Your job is to explain what the figures mean together: why the result is what it is, and the \
    trade-off or implication it creates for the user.

    Rules:
    - Quote only figures that appear in the prompt, copied exactly. Never calculate, estimate or invent \
    a new amount, percentage, date or number of months, and write numbers as digits. If a comparison \
    you want is not listed under relationships, describe it without a number.
    - Keep each figure's meaning from its label: "above" is a surplus and "below" is a shortfall, and a \
    figure labelled "without the purchase" never describes the result with the purchase.
    - A purchase is a one-off cost: it lowers savings once and never changes monthly income, expenses \
    or capacity.
    - Success percentages are shares of simulated paths, not projections: write "X% of simulated paths \
    reach the target", never "projected to reach" or "projected to be X%". P10, P50 and P90 are balances \
    in money, never chances.
    - Do not simply restate the status, and never contradict it. Connect the relevant figures to explain \
    cause and consequence.
    - Address the user as "you". Use short, plain sentences.
    - For the target, deadline, balance or completion, say "is projected to" rather than "will", and use \
    conditional language such as "under these assumptions". Never promise an outcome, even when every \
    simulated path reaches the target.
    - Do not invent causes such as spending habits, and do not tell the user to buy, not buy, \
    or change their income or spending.
    - The summary and the key consideration must make different points; do not repeat a sentence.
    - Choose nextStep only from the next steps listed in the prompt.
    """

    //to configure how responses are generated
    static func options(for sampling: FinancialInsightSampling) -> GenerationOptions {
        switch sampling {
            
        //chooses most likely next tokens, producing repeatable results for the same input
        case .deterministic:
            GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 512)
        
        //introduce some variation when retrying a rejected response
        case .varied:
            GenerationOptions(samplingMode: .random(probabilityThreshold: 0.8), temperature: 0.5,
                              maximumResponseTokens: 512)
        }
    }

    //function to check model availability
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

    //This func receives the financial info and generation settings
    func generate(for request: FinancialInsightRequest,
                  sampling: FinancialInsightSampling) async throws -> GeneratedFinancialInsight {
        
        //check immediately before generation, because availability can change while the app runs.
        guard availability() == .available else { throw FinancialInsightFailure.assetsUnavailable }
        
        //create a fresh conversation with apple's language model using our predefined instructions
        let session = LanguageModelSession(instructions: Self.instructions)
        
        //generate the response
        do {
            
            //call to apple's AI model
            let response = try await session.respond(
                to: Self.prompt(for: request),
                generating: GeneratedFinancialInsight.self,
                options: Self.options(for: sampling)
            )
            
            //return the raw ai generated explanation
            return response.content
        } catch {
            throw Self.failure(for: error)
        }
    }

    //Prompts:

    //Converts the prepared financial request into text the AI can understand.
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

    //Error mapping:

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
