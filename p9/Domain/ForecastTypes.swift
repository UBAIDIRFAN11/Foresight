import Foundation

nonisolated struct ForecastPurchase: Equatable, Sendable {
    let evaluationID: UUID
    let name: String
    let amountMinor: Int64
    let originalAmountMinor: Int64
    let originalCurrencyCode: String
    let rateDescription: String?
}

//a snapshot of the financial inputs, goal, currency, and opt. purchase
nonisolated struct ForecastContext: Equatable, Sendable {
    let goalID: UUID
    let goalName: String
    let currencyCode: String
    let inputs: FinancialInputs
    let purchase: ForecastPurchase?
}

//income/expense variability, simulation count, random seed and model version
nonisolated struct ForecastAssumptions: Equatable, Sendable {
    static let model = "triangular-fixed-point-v1"
    let incomeVariability: Int
    let expenseVariability: Int
    let simulationCount: Int
    let seed: UInt64
    let modelIdentifier: String

    init(incomeVariability: Int = 10, expenseVariability: Int = 15,
         simulationCount: Int = 5_000, seed: UInt64,
         modelIdentifier: String = Self.model) {
        self.incomeVariability = incomeVariability
        self.expenseVariability = expenseVariability
        self.simulationCount = simulationCount
        self.seed = seed
        self.modelIdentifier = modelIdentifier
    }
}

//the context and assumptions packaged with a request ID
nonisolated struct ForecastRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let context: ForecastContext
    let assumptions: ForecastAssumptions

    init(id: UUID = UUID(), context: ForecastContext, assumptions: ForecastAssumptions) {
        self.id = id
        self.context = context
        self.assumptions = assumptions
    }
}

nonisolated struct ForecastPercentiles: Equatable, Sendable {
    let lower: Int64
    let median: Int64
    let upper: Int64

    func subtracting(_ amount: Int64) throws -> Self {
        try Self(lower: ForecastEngine.subtract(lower, amount),
                 median: ForecastEngine.subtract(median, amount),
                 upper: ForecastEngine.subtract(upper, amount))
    }
}

nonisolated struct ForecastSample: Identifiable, Equatable, Sendable {
    let date: Date
    let monthOffset: Int
    let baseline: ForecastPercentiles
    let afterPurchase: ForecastPercentiles?
    var id: Date { date }
}

//monthly percentile summaries, success counts, and deterministic comparison
nonisolated struct ForecastResult: Equatable, Sendable {
    let request: ForecastRequest
    let samples: [ForecastSample]
    let baselineSuccessCount: Int
    let purchaseSuccessCount: Int?
    let deterministicBaselineMinor: Int64
    let deterministicPurchaseMinor: Int64?
    let depositMonths: Int

    var baselinePercentage: Int { percentage(baselineSuccessCount) }
    var purchasePercentage: Int? { purchaseSuccessCount.map(percentage) }
    var reductionPercentagePoints: Int? { purchasePercentage.map { baselinePercentage - $0 } }

    private func percentage(_ count: Int) -> Int {
        (count * 100 + request.assumptions.simulationCount / 2) / request.assumptions.simulationCount
    }
}

nonisolated enum ForecastError: LocalizedError, Equatable, Sendable {
    case invalidInputs, invalidAssumptions, invalidPurchase, pastDeadline, horizonTooLong, overflow, staleSource

    var errorDescription: String? {
        switch self {
        case .invalidInputs: "Check the profile, goal amounts, currency and dates before forecasting."
        case .invalidAssumptions: "Choose variability between 0% and 100%. This model uses 5,000 outcomes."
        case .invalidPurchase: "The purchase must be greater than zero and no higher than current savings."
        case .pastDeadline: "Choose a goal with a deadline today or in the future."
        case .horizonTooLong: "Forecasts support up to 1,200 monthly deposits."
        case .overflow: "These amounts are too large to forecast safely. Reduce them and try again."
        case .staleSource: "This forecast is out of date. Return to the goal or purchase and refresh or recalculate."
        }
    }
}
