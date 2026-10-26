import Foundation

// Swift adaptation of Sebastiano Vigna's public-domain SplitMix64:
// https://prng.di.unimi.it/splitmix64.c
// Wrapping is intentional only inside this pseudorandom generator, never for money.
nonisolated struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}

nonisolated enum ForecastEngine {
    typealias Progress = @Sendable (Int) async -> Void

    // Explicitly leave the caller's actor under the project's approachable concurrency settings.
    @concurrent static func run(
        request: ForecastRequest, progress: Progress = { _ in }
    ) async throws -> ForecastResult {
        var generator = SplitMix64(seed: request.assumptions.seed)
        return try await simulate(request: request, generator: &generator, progress: progress)
    }

    // A single sequential worker keeps memory bounded and the sampling order reproducible.
    // Generic RNG injection also permits scripted fixtures without a second simulation algorithm.
    static func simulate<R: RandomNumberGenerator>(
        request: ForecastRequest, generator: inout R, progress: Progress = { _ in }
    ) async throws -> ForecastResult {
        let months = try validate(request)
        try Task.checkCancellation()
        let input = request.context.inputs
        let assumptions = request.assumptions
        let count = assumptions.simulationCount
        let purchase = request.context.purchase?.amountMinor
        let capacity = try subtract(input.incomeMinor, input.expensesMinor)
        guard let deterministic = FinancialCalculator.balance(
            startingMinor: input.savingsMinor, monthlyCapacityMinor: capacity, months: months
        ) else { throw ForecastError.overflow }
        let deterministicPurchase = try purchase.map { try subtract(deterministic, $0) }
        if months == 0 {
            // No deposit means no random monthly amounts can affect this deadline.
            let summary = ForecastPercentiles(lower: input.savingsMinor, median: input.savingsMinor, upper: input.savingsMinor)
            let after = try purchase.map { try summary.subtracting($0) }
            var samples = [ForecastSample(date: input.evaluationDate, monthOffset: 0,
                                          baseline: summary, afterPurchase: after)]
            if input.targetDate > input.evaluationDate {
                samples.append(ForecastSample(date: input.targetDate, monthOffset: 0,
                                              baseline: summary, afterPurchase: after))
            }
            await progress(0)
            await progress(100)
            try Task.checkCancellation()
            return ForecastResult(request: request, samples: samples,
                                  baselineSuccessCount: input.savingsMinor >= input.targetMinor ? count : 0,
                                  purchaseSuccessCount: deterministicPurchase.map { $0 >= input.targetMinor ? count : 0 },
                                  deterministicBaselineMinor: deterministic, deterministicPurchaseMinor: deterministicPurchase,
                                  depositMonths: 0)
        }
        var balances = [Int64](repeating: input.savingsMinor, count: count)
        var samples: [ForecastSample] = []
        samples.reserveCapacity(months + 2)
        var lastProgress = 0
        await progress(0)

        for month in 0...months {
            if month > 0 {
                for path in balances.indices {
                    if path % 256 == 0 { try Task.checkCancellation() }
                    // Always consume four uniform draws, including zero amount/variability.
                    let income = try sample(input.incomeMinor, percent: assumptions.incomeVariability, generator: &generator)
                    let expenses = try sample(input.expensesMinor, percent: assumptions.expenseVariability, generator: &generator)
                    
                    //next balance = prev. balance + this month's income - this month's expenses
                    balances[path] = try add(balances[path], subtract(income, expenses))
                    if let purchase { _ = try subtract(balances[path], purchase) }
                }
            }
            let summary = try percentiles(balances.sorted())
            try Task.checkCancellation()
            samples.append(ForecastSample(
                date: FinancialCalendar.clampedAnniversary(from: input.evaluationDate, addingMonths: month),
                monthOffset: month, baseline: summary,
                afterPurchase: try purchase.map { try summary.subtracting($0) }
            ))
            let percent = months == 0 ? 100 : month * 100 / months
            if percent > lastProgress {
                lastProgress = percent
                await progress(percent)
            }
        }

        if let last = samples.last, last.date < input.targetDate {
            samples.append(ForecastSample(date: input.targetDate, monthOffset: months,
                                          baseline: last.baseline, afterPurchase: last.afterPurchase))
        }
        var successes = 0
        var purchaseSuccesses = 0
        for (index, balance) in balances.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            if balance >= input.targetMinor { successes += 1 }
            if let purchase, try subtract(balance, purchase) >= input.targetMinor { purchaseSuccesses += 1 }
        }
        try Task.checkCancellation()
        return ForecastResult(request: request, samples: samples, baselineSuccessCount: successes,
                              purchaseSuccessCount: purchase == nil ? nil : purchaseSuccesses,
                              deterministicBaselineMinor: deterministic, deterministicPurchaseMinor: deterministicPurchase,
                              depositMonths: months)
    }

    static func validate(_ request: ForecastRequest) throws -> Int {
        let input = request.context.inputs
        let assumptions = request.assumptions
        guard input.savingsMinor >= 0, input.incomeMinor >= 0, input.expensesMinor >= 0,
              input.targetMinor > 0,
              CurrencyDefinition.supported.contains(where: { $0.code == request.context.currencyCode }),
              validDay(input.evaluationDate), validDay(input.targetDate) else { throw ForecastError.invalidInputs }
        guard (0...100).contains(assumptions.incomeVariability),
              (0...100).contains(assumptions.expenseVariability),
              assumptions.simulationCount == 5_000,
              assumptions.modelIdentifier == ForecastAssumptions.model else { throw ForecastError.invalidAssumptions }
        guard input.targetDate >= input.evaluationDate else { throw ForecastError.pastDeadline }
        if let purchase = request.context.purchase?.amountMinor {
            guard purchase > 0, purchase <= input.savingsMinor else { throw ForecastError.invalidPurchase }
        }
        let months = FinancialCalendar.monthsWithDeposits(from: input.evaluationDate, through: input.targetDate)
        guard months <= FinancialCalculator.completionMonthLimit else { throw ForecastError.horizonTooLong }
        return months
    }

    private static func validDay(_ date: Date) -> Bool {
        guard date.timeIntervalSince1970.isFinite,
              date >= FinancialCalendar.utcNoon(year: 1, month: 1, day: 1),
              date <= FinancialCalendar.utcNoon(year: 9999, month: 12, day: 31) else { return false }
        return date == FinancialCalendar.utcNoon(for: date, in: FinancialCalendar.gregorianUTC)
    }

    // Rejection avoids modulo bias; defining the mapping here makes seeds stable
    // independently of changes to Swift's standard-library random(in:) implementation.
    static func uniform<R: RandomNumberGenerator>(generator: inout R) -> Int64 {
        let bound: UInt64 = 20_001
        let threshold = (0 &- bound) % bound
        var value = generator.next()
        while value < threshold { value = generator.next() }
        return Int64(value % bound) - 10_000
    }

    static func sample<R: RandomNumberGenerator>(_ amount: Int64, percent: Int, generator: inout R) throws -> Int64 {
        let u = uniform(generator: &generator)
        let v = uniform(generator: &generator)
        return try scaledAmount(amount, percent: percent, u: u, v: v)
    }

    static func scaledAmount(_ amount: Int64, percent: Int, u: Int64, v: Int64) throws -> Int64 {
        guard amount >= 0, (0...100).contains(percent),
              (-10_000...10_000).contains(u), (-10_000...10_000).contains(v) else { throw ForecastError.invalidInputs }
        let denominator: Int64 = 2_000_000
        let numerator = denominator + Int64(percent) * (u + v)
        // Split first, so amount * numerator need not fit in Int64.
        let whole = (amount / denominator).multipliedReportingOverflow(by: numerator)
        guard !whole.overflow else { throw ForecastError.overflow }
        let remainderProduct = (amount % denominator) * numerator // bounded below 8e12
        let roundedRemainder = (remainderProduct + denominator / 2) / denominator
        return try add(whole.partialValue, roundedRemainder)
    }

    // Input is sorted. Nearest rank uses integer ceil arithmetic, including P50.
    static func percentiles(_ sorted: [Int64]) throws -> ForecastPercentiles {
        guard !sorted.isEmpty, sorted.count <= 5_000 else { throw ForecastError.invalidInputs }
        func value(_ percentile: Int) -> Int64 {
            sorted[(percentile * sorted.count + 99) / 100 - 1]
        }
        return ForecastPercentiles(lower: value(10), median: value(50), upper: value(90))
    }

    static func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw ForecastError.overflow }
        return result.partialValue
    }

    static func subtract(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.subtractingReportingOverflow(rhs)
        guard !result.overflow else { throw ForecastError.overflow }
        return result.partialValue
    }
}
