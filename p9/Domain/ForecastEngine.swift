import Foundation

//This engine is used to perform the Monte Carlo simulations.
//It runs 5,000 different possible savings scenarios, allowing monthly income and expenses to vary randomly.
//It then analyses the results to estimate how likely the user is to achieve their savings goal.

//the pseudorandom number generator
//by using the same seed and inputs, it produces the same sequence of random numbers, making the simulations reproducible
nonisolated struct SplitMix64: RandomNumberGenerator, Sendable {
    
    //store generator's curr internal state
    private var state: UInt64
    
    //seed: the starting val
    init(seed: UInt64) { state = seed }

    //SplitMix64 algorithm, the random num generation happens here
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

    //this func:
    // - receives a forecasting req,
    // - creates a seeded random num generator
    // - passes it to simulate
    //returns the resulting forecast
    @concurrent static func run(
        request: ForecastRequest, progress: Progress = { _ in }
    ) async throws -> ForecastResult {
        var generator = SplitMix64(seed: request.assumptions.seed)
        return try await simulate(request: request, generator: &generator, progress: progress)
    }

    //the main MC algorithm
    static func simulate<R: RandomNumberGenerator>(
        request: ForecastRequest, generator: inout R, progress: Progress = { _ in }
    ) async throws -> ForecastResult {
        
        //check that the inputs are valid and task hasn't been cancelled
        let months = try validate(request)
        try Task.checkCancellation()
        let input = request.context.inputs
        let assumptions = request.assumptions
        let count = assumptions.simulationCount
        let purchase = request.context.purchase?.amountMinor
        
        //calculate the deterministic outcome (baseline result assuming no variability) for comparison:
        
        //calculate monthly savings capacity
        let capacity = try subtract(input.incomeMinor, input.expensesMinor)
        
        //calculate deterministic baseline
        guard let deterministic = FinancialCalculator.balance(
            startingMinor: input.savingsMinor, monthlyCapacityMinor: capacity, months: months
        ) else { throw ForecastError.overflow }
        
        //calculate deterministic res after a purchase
        let deterministicPurchase = try purchase.map { try subtract(deterministic, $0) }
        
        
        if months == 0 {
            // No deposit means no random monthly amounts can affect this deadline.
            //therefore, no reason to run the 5000 sims, so we immediately create the result based on user's curr savings
            let summary = ForecastPercentiles(lower: input.savingsMinor, median: input.savingsMinor, upper: input.savingsMinor)
            let after = try purchase.map { try summary.subtracting($0) }
            
            //create the first forecast sample
            var samples = [ForecastSample(date: input.evaluationDate, monthOffset: 0,
                                          baseline: summary, afterPurchase: after)]
            
            //add another sample at deadline if goal deadline is later than eval date
            if input.targetDate > input.evaluationDate {
                samples.append(ForecastSample(date: input.targetDate, monthOffset: 0,
                                              baseline: summary, afterPurchase: after))
            }
            await progress(0)
            await progress(100)
            try Task.checkCancellation()
            
            //construct and return the forecast result
            //  - baselineSuccessCount: if curr savings >= target, all sims count as ssuccessful, otherwise none do
            return ForecastResult(request: request, samples: samples,
                                  baselineSuccessCount: input.savingsMinor >= input.targetMinor ? count : 0,
                                  purchaseSuccessCount: deterministicPurchase.map { $0 >= input.targetMinor ? count : 0 },
                                  deterministicBaselineMinor: deterministic, deterministicPurchaseMinor: deterministicPurchase,
                                  depositMonths: 0)
        }
        
        //create count amount of savings balances, each with the same initial savings amount
        var balances = [Int64](repeating: input.savingsMinor, count: count)
        var samples: [ForecastSample] = []
        samples.reserveCapacity(months + 2)
        var lastProgress = 0
        await progress(0)

        
        //run the simulations month by month
        for month in 0...months {
            if month > 0 {
                
                //loop through all simulation paths
                for path in balances.indices {
                    if path % 256 == 0 { try Task.checkCancellation() }
                    
                    
                    //randomly generate this month's income
                    let income = try sample(input.incomeMinor, percent: assumptions.incomeVariability, generator: &generator)
                    
                    //randomly generate this month's expenses
                    let expenses = try sample(input.expensesMinor, percent: assumptions.expenseVariability, generator: &generator)
                    
                    //next balance = prev. balance + this month's income - this month's expenses
                    balances[path] = try add(balances[path], subtract(income, expenses))
                    if let purchase { _ = try subtract(balances[path], purchase) }
                }
            }
            
            //take the current month's savings balances and calculate 3 statistical vals:
                //P10 - lower 10th percentile
                //P50 - median balance
                //upper 90th percentile
            // sort balances from smallest to largest
            let summary = try percentiles(balances.sorted())
            try Task.checkCancellation()
            
            //add a forecast sample for this month
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

        //check if last sample comes before deadline
        if let last = samples.last, last.date < input.targetDate {
            samples.append(ForecastSample(date: input.targetDate, monthOffset: months,
                                          baseline: last.baseline, afterPurchase: last.afterPurchase))
        }
        
        //caclulate pr of reaching the savings goal
        var successes = 0
        var purchaseSuccesses = 0
        
        //loop through the final balances
        for (index, balance) in balances.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            
            //count successful baseline scenarios
            //a success is when the balance >= target
            if balance >= input.targetMinor { successes += 1 }
            
            //count successful after purchase  scenarios
            if let purchase, try subtract(balance, purchase) >= input.targetMinor { purchaseSuccesses += 1 }
        }
        try Task.checkCancellation()
        
        //return the final forecast result, packaging all the simulation info into one obj
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
