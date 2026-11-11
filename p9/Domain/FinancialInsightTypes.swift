import Foundation
import FoundationModels

//Defines the data structures used by the AI feature.
//it doesn't generate the actual explanations it self, it just defines what the AI receives, what it should return, and how errors are represented.


//Stores a copy of the information needed to explain a savings goal's progress.
nonisolated struct GoalInsightSnapshot: Equatable, Sendable {
    let source: ForecastContext
    let result: FinancialCalculationResult
}

//Stores info about an evaluated purchase, including its amount, associated goal and calculated impact.
nonisolated struct PurchaseInsightSnapshot: Equatable, Sendable {
    let evaluationID: UUID
    let goalID: UUID
    let currencyCode: String
    let purchaseAmountMinor: Int64
    let originalSavingsMinor: Int64
    let goalTargetMinor: Int64
    let goalTargetDate: Date
    let evaluationDate: Date
    let result: PurchaseImpactResult
    let wasConverted: Bool
}

//Stores the key results of a completed Monte Carlo forecast, including success probabilities, percentiles and deterministic outcomes.
nonisolated struct ForecastInsightSnapshot: Equatable, Sendable {
    let requestID: UUID
    let context: ForecastContext
    let incomeVariability: Int
    let expenseVariability: Int
    let simulationCount: Int
    let modelIdentifier: String
    let baselineSuccessCount: Int
    let purchaseSuccessCount: Int?
    let baselinePercentage: Int
    let purchasePercentage: Int?
    let reductionPercentagePoints: Int?
    let baselineDeadline: ForecastPercentiles
    let purchaseDeadline: ForecastPercentiles?
    let deterministicBaselineMinor: Int64
    let deterministicPurchaseMinor: Int64?
    let depositMonths: Int

    var includesPurchase: Bool { purchaseSuccessCount != nil }
}

//supported explanation types.
//They each receive a snapshot, which contains a copy of the relevant, already calculated info
nonisolated enum FinancialInsightContext: Equatable, Sendable {
    
    //explains goal progression
    case goal(GoalInsightSnapshot)
    
    //explains impact of a hypothetical purchase on a goal
    case purchase(PurchaseInsightSnapshot)
    
    //explains probabalistic forecast results.
    case forecast(ForecastInsightSnapshot)
}

//Represents a verified financial figure calculated by the app
nonisolated struct FinancialInsightFact: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
}

// A scenario-specific next step. the app decides which steps apply and writes the text;
// the model only chooses among them.
nonisolated struct FinancialInsightSuggestion: Equatable, Sendable {
    let step: FinancialInsightNextStep
    let text: String
}

// Created once per explicit button tap.
//this contains everything needed to generate an explanation.
nonisolated struct FinancialInsightRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    
    //the type of financial result being explained
    let context: FinancialInsightContext
    let title: String
    // The result the user already sees on the originating screen.
    let status: String
    // Verified figures copied from the existing result.
    let facts: [FinancialInsightFact]
    
    //pre-calculated comparisons between figures
    let relationships: [String]
    
    //instructions for interpreting the results correctly
    let rules: [String]
    
    // What the summary and the key consideration should focus on for this scenario.
    let focus: String
    let considerationFocus: String
    
    // Relevant next steps for this scenario, most relevant first.
    let suggestions: [FinancialInsightSuggestion]
    
    let uncertaintyNote: String

    var permittedNextSteps: [FinancialInsightNextStep] { suggestions.map(\.step) }

    //assign the supplied vals to the request's properties
    init(id: UUID = UUID(), context: FinancialInsightContext, title: String, status: String,
         facts: [FinancialInsightFact], relationships: [String], rules: [String], focus: String,
         considerationFocus: String, suggestions: [FinancialInsightSuggestion], uncertaintyNote: String) {
        self.id = id
        self.context = context
        self.title = title
        self.status = status
        self.facts = facts
        self.relationships = relationships
        self.rules = rules
        self.focus = focus
        self.considerationFocus = considerationFocus
        self.suggestions = suggestions
        self.uncertaintyNote = uncertaintyNote
    }
}


//@Generable tells the Foundation models framework that the AI can generate a value of this type
@Generable
nonisolated enum FinancialInsightNextStep: String, CaseIterable, Equatable, Sendable {
    
    //the model chooses from the defined enum cases.
    case reviewProfile
    case reviewGoal
    case compareSmallerPurchase
    case reviewForecastAssumptions
    case runForecast
    case testPurchase
}

//this generates the raw AI response (not necessarily the final one shown to user)
@Generable
nonisolated struct GeneratedFinancialInsight: Equatable, Sendable {
    @Guide(description: "Two or three short sentences addressed to you. Explain why the result is what it is and what it implies, quoting the relevant verified figures exactly. Do not just restate the status.")
    let summary: String //main explanation

    @Guide(description: "One sentence about the key point named in the prompt, adding something not already in the summary. Quote verified figures exactly if useful.")
    let keyConsideration: String //another important key point to consider

    @Guide(description: "The most relevant next step from the options listed in the prompt.")
    let nextStep: FinancialInsightNextStep //a suggested action selected from the predefined options
}

// Accepted output.
nonisolated struct ValidatedFinancialInsight: Equatable, Sendable {
    let summary: String
    let keyConsideration: String
    let suggestion: FinancialInsightSuggestion
}

//Availability and failures

nonisolated enum FinancialInsightAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedLanguage
    case unavailable

    var title: String {
        switch self {
        case .available: "Available"
        case .deviceNotEligible: "Not Supported on This Device"
        case .appleIntelligenceNotEnabled: "Apple Intelligence Is Off"
        case .modelNotReady: "Model Not Ready"
        case .unsupportedLanguage: "Language Not Supported"
        case .unavailable: "AI Explanations Unavailable"
        }
    }

    var message: String {
        switch self {
        case .available:
            "On-device explanations are available."
        case .deviceNotEligible:
            "This device does not support Apple Intelligence. Your Foresight calculations are unaffected."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to use AI explanations. Your Foresight calculations are unaffected."
        case .modelNotReady:
            "The on-device model is still downloading or preparing. Try again later."
        case .unsupportedLanguage:
            "AI explanations currently support English only. Your Foresight calculations are unaffected."
        case .unavailable:
            "The on-device model is unavailable right now. Your Foresight calculations are unaffected."
        }
    }

    // Model-not-ready can resolve while the sheet is open, so it offers Check Again.
    var canCheckAgain: Bool { self == .modelNotReady || self == .unavailable }
}

// How an attempt samples. The first attempt is greedy and repeatable; greedy output for the same
// prompt never changes, so a retry after a rejected response uses modest random sampling instead.
nonisolated enum FinancialInsightSampling: Equatable, Sendable {
    case deterministic
    case varied
}

nonisolated enum FinancialInsightFailure: Error, Equatable, Sendable {
    case refused
    case guardrailViolation
    case assetsUnavailable
    case contextTooLarge
    case unsupportedLanguage
    case unusableResponse
    // Every permitted attempt was rejected by the validator; retrying further is not offered.
    case noReliableExplanation
    case busy
    case unexpected

    var message: String {
        switch self {
        case .refused:
            "The model declined to explain this result. Your Foresight figures above are unaffected."
        case .guardrailViolation:
            "The on-device safety checks blocked this explanation. Your Foresight figures above are unaffected."
        case .assetsUnavailable:
            "The on-device model is not available right now. Try again later."
        case .contextTooLarge:
            "This result was too large to explain on this device."
        case .unsupportedLanguage:
            "AI explanations currently support English only."
        case .unusableResponse:
            "The generated explanation did not meet Foresight's accuracy rules, so it was not shown."
        case .noReliableExplanation:
            "Foresight could not generate an explanation that met its accuracy rules for this result. Your Foresight figures above are unaffected."
        case .busy:
            "The on-device model is busy. Wait a moment and try again."
        case .unexpected:
            "Something went wrong while generating the explanation."
        }
    }

    // Retry uses the same snapshot with a fresh session.
    var canRetry: Bool {
        switch self {
        case .contextTooLarge, .unsupportedLanguage, .noReliableExplanation: false
        default: true
        }
    }
}

// Shared AI wording for stale goal, purchase and forecast sources.
nonisolated struct FinancialInsightStaleSourceError: LocalizedError, Equatable {
    var errorDescription: String? {
        "This explanation is out of date because the underlying result changed. Close this sheet and request a new explanation."
    }
}

// Raised before any model call when a displayed result cannot be explained safely.
nonisolated enum FinancialInsightContextError: LocalizedError, Equatable, Sendable {
    case unsupportedGoalResult
    case invalidPurchase
    case incompleteForecast

    var errorDescription: String? {
        switch self {
        case .unsupportedGoalResult: "This goal's calculation cannot be explained. Check the profile and goal amounts."
        case .invalidPurchase: "This purchase result cannot be explained."
        case .incompleteForecast: "This forecast result is incomplete and cannot be explained."
        }
    }
}
