import Foundation

// Adapts three existing, already-calculated results into explanation requests.
// None of these adapters calls FinancialCalculator, PurchaseImpactCalculator, ForecastEngine
// or an exchange-rate service. They copy, validate and format existing values, and state
// relationships between them using only checked subtraction (for example, capacity against
// the required contribution), so the model never has to calculate.
enum FinancialInsightContextBuilder {

    //Snapshots

    static func goalSnapshot(source: ForecastContext, result: FinancialCalculationResult) throws -> GoalInsightSnapshot {
        // Invalid and overflow results have no meaningful explanation.
        guard result.status != .invalidInputs, result.status != .overflow,
              source.purchase == nil else { throw FinancialInsightContextError.unsupportedGoalResult }
        return GoalInsightSnapshot(source: source, result: result)
    }

    static func purchaseSnapshot(evaluation: PurchaseImpactEvaluation) throws -> PurchaseInsightSnapshot {
        let result = evaluation.result
        // A normal evaluation already passed the available-savings check; reject anything that did not.
        guard evaluation.purchaseAmountMinor > 0,
              evaluation.purchaseAmountMinor <= evaluation.originalSavingsMinor,
              result.remainingSavingsMinor >= 0,
              ![GoalFundingStatus.invalidInputs, .overflow].contains(result.baseline.status),
              ![GoalFundingStatus.invalidInputs, .overflow].contains(result.afterPurchase.status) else {
            throw FinancialInsightContextError.invalidPurchase
        }
        return PurchaseInsightSnapshot(
            evaluationID: evaluation.id, goalID: evaluation.goalID, currencyCode: evaluation.currencyCode,
            purchaseAmountMinor: evaluation.purchaseAmountMinor, originalSavingsMinor: evaluation.originalSavingsMinor,
            goalTargetMinor: evaluation.goalTargetMinor, goalTargetDate: evaluation.goalTargetDate,
            evaluationDate: evaluation.evaluationDate, result: result, wasConverted: evaluation.conversion != nil
        )
    }

    static func forecastSnapshot(result: ForecastResult) throws -> ForecastInsightSnapshot {
        let request = result.request
        let assumptions = request.assumptions
        let count = assumptions.simulationCount
        let hasPurchase = request.context.purchase != nil
        // The explanation concerns the deadline summary, so the final sample must be the deadline.
        guard count > 0, assumptions.modelIdentifier == ForecastAssumptions.model,
              let deadline = result.samples.last, deadline.date == request.context.inputs.targetDate,
              (0...count).contains(result.baselineSuccessCount),
              isOrdered(deadline.baseline),
              hasPurchase == (result.purchaseSuccessCount != nil),
              hasPurchase == (deadline.afterPurchase != nil),
              hasPurchase == (result.deterministicPurchaseMinor != nil),
              result.depositMonths >= 0 else { throw FinancialInsightContextError.incompleteForecast }
        if let purchaseCount = result.purchaseSuccessCount, let after = deadline.afterPurchase {
            guard (0...count).contains(purchaseCount), isOrdered(after) else {
                throw FinancialInsightContextError.incompleteForecast
            }
        }
        return ForecastInsightSnapshot(
            requestID: request.id, context: request.context,
            incomeVariability: assumptions.incomeVariability, expenseVariability: assumptions.expenseVariability,
            simulationCount: count, modelIdentifier: assumptions.modelIdentifier,
            baselineSuccessCount: result.baselineSuccessCount, purchaseSuccessCount: result.purchaseSuccessCount,
            baselinePercentage: result.baselinePercentage, purchasePercentage: result.purchasePercentage,
            reductionPercentagePoints: result.reductionPercentagePoints,
            baselineDeadline: deadline.baseline, purchaseDeadline: deadline.afterPurchase,
            deterministicBaselineMinor: result.deterministicBaselineMinor,
            deterministicPurchaseMinor: result.deterministicPurchaseMinor,
            depositMonths: result.depositMonths
        )
    }

    private static func isOrdered(_ percentiles: ForecastPercentiles) -> Bool {
        percentiles.lower <= percentiles.median && percentiles.median <= percentiles.upper
    }

    //Requests

    static func goalRequest(source: ForecastContext, result: FinancialCalculationResult) throws -> FinancialInsightRequest {
        request(for: .goal(try goalSnapshot(source: source, result: result)))
    }

    static func purchaseRequest(evaluation: PurchaseImpactEvaluation) throws -> FinancialInsightRequest {
        request(for: .purchase(try purchaseSnapshot(evaluation: evaluation)))
    }

    static func forecastRequest(result: ForecastResult) throws -> FinancialInsightRequest {
        request(for: .forecast(try forecastSnapshot(result: result)))
    }

    static func request(for context: FinancialInsightContext) -> FinancialInsightRequest {
        switch context {
        case .goal(let snapshot): goalRequest(snapshot, context: context)
        case .purchase(let snapshot): purchaseRequest(snapshot, context: context)
        case .forecast(let snapshot): forecastRequest(snapshot, context: context)
        }
    }

    //Goal

    private static func goalRequest(_ snapshot: GoalInsightSnapshot, context: FinancialInsightContext) -> FinancialInsightRequest {
        let inputs = snapshot.source.inputs
        let result = snapshot.result
        let money = moneyFormatter(snapshot.source.currencyCode)
        let hasDeposits = result.monthsToDeadline > 0
        // The calculator reports zero in both cases below; say why instead of showing $0.00.
        let required = result.remainingMinor == 0
            ? "Not needed: savings already meet the target"
            : !hasDeposits ? "Not applicable: no monthly deposit before the deadline" : money(result.monthlyRequiredMinor)

        let facts = [
            FinancialInsightFact(id: "target", label: "Goal target", value: money(inputs.targetMinor)),
            FinancialInsightFact(id: "savings", label: "Current savings", value: money(inputs.savingsMinor)),
            FinancialInsightFact(id: "progress", label: "Funded now", value: progressText(result.progress)),
            FinancialInsightFact(id: "capacity", label: "Monthly capacity (income minus expenses)", value: money(result.monthlyCapacityMinor)),
            FinancialInsightFact(id: "required", label: "Required each month to reach the target by the deadline", value: required),
            FinancialInsightFact(id: "deposits", label: "Number of monthly deposits before the deadline", value: "\(result.monthsToDeadline)"),
            FinancialInsightFact(id: "deadline", label: "Deadline", value: formatted(inputs.targetDate)),
            FinancialInsightFact(id: "deadlineBalance", label: "Projected balance on the deadline", value: money(result.deadlineBalanceMinor)),
            FinancialInsightFact(id: "completion", label: "Projected completion", value: completionText(result.completionProjection))
        ]

        var relationships: [String] = []
        // Savings against the target today, when it is the comparison the explanation turns on:
        // already funded, or no deposit can count before the deadline. The model otherwise
        // calculated this difference itself.
        if result.remainingMinor == 0 || result.status == .pastDeadline || result.status == .noContributionBeforeDeadline,
           let difference = magnitude(of: inputs.savingsMinor, minus: inputs.targetMinor) {
            relationships.append(inputs.savingsMinor == inputs.targetMinor
                ? "Current savings exactly match the target today."
                : inputs.savingsMinor > inputs.targetMinor
                    ? "Current savings are \(money(difference)) above the target today."
                    : "Current savings are \(money(difference)) below the target today.")
        }
        // Capacity against the required contribution, only when deposits remain and money is still needed.
        // With zero or negative capacity the gap reads as a large "less than required" figure that
        // the deficit relationship below explains more plainly, so it is only stated for positive capacity.
        if hasDeposits, result.monthlyCapacityMinor > 0, result.remainingMinor > 0, result.status != .pastDeadline,
           let gap = magnitude(of: result.monthlyCapacityMinor, minus: result.monthlyRequiredMinor) {
            relationships.append(result.monthlyCapacityMinor >= result.monthlyRequiredMinor
                ? "Monthly capacity is \(money(gap)) more than the amount required each month."
                : "Monthly capacity is \(money(gap)) less than the amount required each month.")
        }
        if result.monthlyCapacityMinor < 0 {
            relationships.append("Expenses exceed income by \(money(-result.monthlyCapacityMinor)) each month, so the balance falls over time.")
        } else if result.monthlyCapacityMinor == 0 {
            // Without this the model filled the gap with advice to change income or expenses.
            relationships.append("Income exactly matches expenses, so the balance stays at current savings and does not grow.")
        }
        if result.status != .pastDeadline,
           let margin = magnitude(of: result.deadlineBalanceMinor, minus: inputs.targetMinor) {
            relationships.append(result.deadlineBalanceMinor >= inputs.targetMinor
                ? "On the deadline, the projected balance is \(money(margin)) above the target."
                : "On the deadline, the projected balance is \(money(margin)) below the target.")
        }
        // Compare by date: a deposit count alone read like "months early" when it was not.
        // With no deposit before the deadline, every projected deposit falls after it; stating the
        // count stops the model working out the gap itself (it produced 2 and 10 for a 4-deposit gap).
        if case .projected(let months, let date) = result.completionProjection,
           hasDeposits || result.status == .noContributionBeforeDeadline {
            if months > result.monthsToDeadline {
                let extra = months - result.monthsToDeadline
                let plural = { (count: Int) in count == 1 ? "deposit" : "deposits" }
                // Both counts are stated: the model once quoted the completion duration as the
                // number of deposits "by the deadline".
                relationships.append(result.monthsToDeadline > 0
                    ? "The target is projected to be reached on \(formatted(date)), after the \(formatted(inputs.targetDate)) deadline: \(result.monthsToDeadline) monthly \(plural(result.monthsToDeadline)) occur before the deadline, and \(extra) more \(extra == 1 ? "is" : "are") needed after it."
                    : "The target is projected to be reached on \(formatted(date)), after the \(formatted(inputs.targetDate)) deadline, needing \(extra) more monthly \(plural(extra)).")
            } else if months < result.monthsToDeadline {
                relationships.append("The target is projected to be reached on \(formatted(date)), before the \(formatted(inputs.targetDate)) deadline.")
            }
        }
        if result.remainingMinor == 0, case .atRisk = result.status {
            relationships.append("Your savings meet the target today, but they are projected to fall below it by the deadline.")
        }

        return FinancialInsightRequest(
            context: context, title: "Your goal", status: statusText(result.status), facts: facts,
            relationships: relationships,
            rules: [
                "This goal uses all of your profile savings and monthly capacity on its own; savings are not split between goals.",
                "Projections assume income and expenses stay as entered."
            ],
            focus: goalFocus(result),
            considerationFocus: goalConsiderationFocus(snapshot),
            suggestions: goalSuggestions(snapshot),
            uncertaintyNote: "Projections assume your income and expenses stay as entered, and each goal uses your full savings independently."
        )
    }

    // Asking for a capacity-versus-required comparison when nothing is required led the model
    // to pair unrelated figures, so the summary focus follows the scenario.
    private static func goalFocus(_ result: FinancialCalculationResult) -> String {
        switch result.status {
        case .pastDeadline, .noContributionBeforeDeadline:
            return "Explain why only your current savings count toward this deadline, and how far they are from the target."
        default:
            break
        }
        // An open question about zero capacity drew advice to change income or expenses.
        if result.monthlyCapacityMinor == 0 {
            return "Explain why your savings stay at their current level when income only matches expenses, and how far that leaves the balance from the target on the deadline."
        }
        if result.monthlyCapacityMinor < 0 {
            return "Explain what your monthly capacity does to your savings before the deadline, and what that means for this goal's target."
        }
        if result.remainingMinor == 0 {
            // Mentioning monthly capacity here led the model to invent a monthly deposit amount.
            return "Explain what your savings being above the target today and the projected margin on the deadline mean together."
        }
        return "Explain how your monthly capacity compares with what this goal requires each month, and what that means for when the target is reached relative to the deadline."
    }

    // A scenario-specific key point, kept distinct from the summary's material. An open-ended
    // instruction often led the model to repeat its summary word for word.
    private static func goalConsiderationFocus(_ snapshot: GoalInsightSnapshot) -> String {
        let result = snapshot.result
        let money = moneyFormatter(snapshot.source.currencyCode)
        // The summary already explains what the capacity does to savings; asking about the deficit
        // again made the model repeat that sentence in both fields.
        if result.monthlyCapacityMinor < 0 {
            return "why Foresight cannot project a completion date for this goal while your balance falls each month."
        }
        if result.monthlyCapacityMinor == 0 {
            return "why Foresight cannot project a completion date for this goal while income only matches expenses."
        }
        switch result.status {
        case .onTrack, .fundedNow:
            if let margin = magnitude(of: result.deadlineBalanceMinor, minus: snapshot.source.inputs.targetMinor) {
                return "what the \(money(margin)) margin above the target at the deadline depends on, given that it assumes income and expenses stay as entered."
            }
            return "how much room this result has before it would slip, given that it assumes income and expenses stay as entered."
        // The summary already explains why only current savings count, so the key point moves on.
        case .pastDeadline:
            return "why Foresight cannot project progress toward a deadline that has already passed."
        case .noContributionBeforeDeadline:
            if case .projected(_, let date) = result.completionProjection {
                return "how the projected completion on \(formatted(date)) compares with the \(formatted(snapshot.source.inputs.targetDate)) deadline, since monthly deposits only start after it."
            }
            return "what your monthly capacity can and cannot change before this deadline."
        default:
            return "what the shortfall depends on: the gap between your capacity and the amount required, if income and expenses stay as entered."
        }
    }

    private static func goalSuggestions(_ snapshot: GoalInsightSnapshot) -> [FinancialInsightSuggestion] {
        let result = snapshot.result
        let money = moneyFormatter(snapshot.source.currencyCode)
        let runForecast = FinancialInsightSuggestion(step: .runForecast,
            text: "Run Forecast Uncertainty to see how often this goal still succeeds if income and expenses vary.")
        switch result.status {
        case .pastDeadline:
            return [FinancialInsightSuggestion(step: .reviewGoal,
                text: "Update this goal's deadline in Edit. It has already passed, so Foresight cannot project it.")]
        case .noContributionBeforeDeadline:
            return [FinancialInsightSuggestion(step: .reviewGoal,
                text: "Review the deadline. No monthly deposit occurs before it, so only your current \(money(snapshot.source.inputs.savingsMinor)) counts toward the \(money(snapshot.source.inputs.targetMinor)) target.")]
        default:
            break
        }
        if result.monthlyCapacityMinor <= 0 {
            return [FinancialInsightSuggestion(step: .reviewProfile,
                text: "Check that your profile's income and expenses are current. With \(money(result.monthlyCapacityMinor)) monthly capacity, savings cannot grow toward this goal.")]
        }
        switch result.status {
        case .onTrack, .fundedNow:
            return [
                runForecast,
                FinancialInsightSuggestion(step: .testPurchase,
                    text: "Use the simulator to check how a planned purchase would affect this goal before the deadline.")
            ]
        default:
            // At risk with positive capacity: the plan needs more each month than the profile provides.
            let text = result.monthsToDeadline > 0 && result.monthlyRequiredMinor > result.monthlyCapacityMinor
                ? "Edit the goal to try a later deadline or smaller target. The plan needs \(money(result.monthlyRequiredMinor)) a month, but your capacity is \(money(result.monthlyCapacityMinor))."
                : "Edit the goal to try a later deadline or smaller target that fits your \(money(result.monthlyCapacityMinor)) monthly capacity."
            return [FinancialInsightSuggestion(step: .reviewGoal, text: text), runForecast]
        }
    }

    //Purchase

    private static func purchaseRequest(_ snapshot: PurchaseInsightSnapshot, context: FinancialInsightContext) -> FinancialInsightRequest {
        let result = snapshot.result
        let money = moneyFormatter(snapshot.currencyCode)
        let target = snapshot.goalTargetMinor
        let cost = MoneyFormatting.display(snapshot.purchaseAmountMinor, currencyCode: snapshot.currencyCode,
                                           includeCode: snapshot.wasConverted)
        let missesBefore = result.deadlineBalanceBeforeMinor < target
        let missesAfter = result.deadlineBalanceAfterMinor < target
        // Only the figures that matter for this scenario; a long list led the model to pair unrelated values.
        var facts = [
            FinancialInsightFact(id: "cost", label: snapshot.wasConverted ? "Converted purchase cost" : "Purchase cost", value: cost),
            FinancialInsightFact(id: "savingsBefore", label: "Savings before the purchase", value: money(snapshot.originalSavingsMinor)),
            FinancialInsightFact(id: "savingsAfter", label: "Savings after the purchase", value: money(result.remainingSavingsMinor)),
            FinancialInsightFact(id: "target", label: "Goal target", value: money(target)),
            FinancialInsightFact(id: "deadline", label: "Deadline", value: formatted(snapshot.goalTargetDate)),
            FinancialInsightFact(id: "deadlineBefore", label: "Deadline balance without the purchase", value: money(result.deadlineBalanceBeforeMinor)),
            FinancialInsightFact(id: "deadlineAfter", label: "Deadline balance with the purchase", value: money(result.deadlineBalanceAfterMinor)),
            FinancialInsightFact(id: "delay", label: "Completion delay", value: metricText(result.purchaseDelay, currencyCode: snapshot.currencyCode))
        ]
        if case .amount(let extra) = result.extraMonthlySavings, extra > 0 {
            facts.append(FinancialInsightFact(id: "extraMonthly", label: "Extra monthly saving needed to keep the deadline after the purchase", value: money(extra)))
            facts.append(FinancialInsightFact(id: "capacity", label: "Monthly capacity", value: money(result.baseline.monthlyCapacityMinor)))
        }
        let maximum = result.maximumPurchasePreservingDeadline.amountMinor
        if missesAfter, let maximum {
            facts.append(FinancialInsightFact(id: "maximum", label: "Largest purchase that keeps the deadline balance at the target", value: money(maximum)))
        }

        // The first relationship states the outcome for the goal in plain words.
        var relationships: [String] = []
        if let before = magnitude(of: result.deadlineBalanceBeforeMinor, minus: target),
           let after = magnitude(of: result.deadlineBalanceAfterMinor, minus: target) {
            if missesBefore {
                relationships.append("Even without the purchase, the projected deadline balance is \(money(before)) below the target; with it, the gap is \(money(after)).")
            } else if missesAfter {
                relationships.append("The purchase takes the goal from \(money(before)) above the target at the deadline to \(money(after)) below it.")
            } else {
                // State the margin change itself: the model otherwise subtracted the two margins,
                // once getting $1,450.00 for a $1,500.00 change.
                let change = magnitude(of: before, minus: after).map { ", a fall of \(money($0))" } ?? ""
                let completion = if let delay = result.purchaseDelay.monthCount, delay > 0 {
                    "but completion moves \(delay) \(delay == 1 ? "month" : "months") later."
                } else {
                    "and the completion month does not change."
                }
                relationships.append("The goal still ends above the target at the deadline: the margin above the target goes from \(money(before)) without the purchase to \(money(after)) with it\(change), \(completion)")
            }
        }
        // The purchase is an immediate cost, so it lowers savings and the deadline balance by exactly its cost.
        // It is a one-off cost: the model otherwise sometimes described it as lowering monthly capacity.
        relationships.append("The purchase lowers both your savings and the projected deadline balance by its cost, \(money(snapshot.purchaseAmountMinor)). It is a one-off cost, so your \(money(result.baseline.monthlyCapacityMinor)) monthly capacity does not change.")
        // When the purchase causes the miss, its excess over the deadline-keeping limit is the key point.
        var considerationFocus = "why the remaining margin depends on income and expenses staying as entered."
        if missesBefore {
            considerationFocus = "the goal already being below the target at the deadline even without the purchase."
        } else if missesAfter, let maximum, snapshot.purchaseAmountMinor > maximum,
                  let excess = magnitude(of: snapshot.purchaseAmountMinor, minus: maximum) {
            considerationFocus = "the cost being \(money(excess)) more than the \(money(maximum)) largest purchase that keeps the deadline balance at the target."
        } else if missesAfter {
            considerationFocus = "how far the purchase moves the goal below its target at the deadline."
        }
        if case .amount(let extra) = result.extraMonthlySavings, extra > 0 {
            relationships.append("Keeping the deadline after the purchase would need \(money(extra)) more each month on top of the \(money(result.baseline.monthlyCapacityMinor)) capacity.")
        }

        return FinancialInsightRequest(
            context: context, title: "This purchase",
            status: "Without the purchase: \(result.baseline.status.summaryTitle). With the purchase: \(result.afterPurchase.status.summaryTitle).",
            facts: facts, relationships: relationships,
            rules: [
                "Being able to pay from savings is not a judgement that buying it is advisable.",
                "Describe the effect on the goal; never describe the purchase itself as succeeding or failing."
            ],
            // The cost against the deadline-keeping limit is the key consideration's point; asking the
            // summary for it as well made the model state it in both fields.
            focus: missesAfter
                ? "Explain the trade-off: what paying for this from savings does to the goal's deadline balance and completion."
                : "Explain the trade-off: what paying for this from savings does to the goal's margin above the target at the deadline and to its completion.",
            considerationFocus: considerationFocus,
            suggestions: purchaseSuggestions(snapshot),
            uncertaintyNote: "A hypothetical result using your current income and expenses; nothing has been bought, saved or changed."
        )
    }

    private static func purchaseSuggestions(_ snapshot: PurchaseInsightSnapshot) -> [FinancialInsightSuggestion] {
        let result = snapshot.result
        let money = moneyFormatter(snapshot.currencyCode)
        let target = snapshot.goalTargetMinor
        let runForecast = FinancialInsightSuggestion(step: .runForecast,
            text: "Run Forecast Uncertainty to see how this purchase changes the goal's chance of reaching the target when income and expenses vary.")
        if result.baseline.monthlyCapacityMinor <= 0 {
            return [FinancialInsightSuggestion(step: .reviewProfile,
                text: "Check that your profile's income and expenses are current. With \(money(result.baseline.monthlyCapacityMinor)) monthly capacity, this goal cannot grow after the purchase.")]
        }
        if result.deadlineBalanceAfterMinor < target {
            if result.deadlineBalanceBeforeMinor < target {
                return [FinancialInsightSuggestion(step: .reviewGoal,
                    text: "Review this goal's deadline or target first. It falls short at the deadline even without the purchase."), runForecast]
            }
            if let maximum = result.maximumPurchasePreservingDeadline.amountMinor, maximum > 0 {
                return [FinancialInsightSuggestion(step: .compareSmallerPurchase,
                    text: "Adjust the amount to \(money(maximum)) or less to compare a purchase that keeps the projected deadline balance at the target."), runForecast]
            }
            return [FinancialInsightSuggestion(step: .compareSmallerPurchase,
                text: "Adjust the amount to compare a smaller purchase against this goal's deadline."), runForecast]
        }
        if let delay = result.purchaseDelay.monthCount, delay > 0 {
            return [runForecast, FinancialInsightSuggestion(step: .compareSmallerPurchase,
                text: "Adjust the amount to see how a smaller purchase changes the \(delay)-month completion delay.")]
        }
        return [runForecast]
    }

    //Forecast

    private static func forecastRequest(_ snapshot: ForecastInsightSnapshot, context: FinancialInsightContext) -> FinancialInsightRequest {
        let inputs = snapshot.context.inputs
        let target = inputs.targetMinor
        let money = moneyFormatter(snapshot.context.currencyCode)
        let paths = snapshot.simulationCount.formatted()
        func success(_ percentage: Int, _ count: Int) -> String {
            "\(percentage)% (rounded) · \(count.formatted()) of \(paths) paths"
        }
        func percentiles(_ prefix: String, _ id: String, _ values: ForecastPercentiles) -> [FinancialInsightFact] {
            [FinancialInsightFact(id: "\(id)P10", label: "\(prefix)P10 deadline balance", value: money(values.lower)),
             FinancialInsightFact(id: "\(id)P50", label: "\(prefix)P50 (median) deadline balance", value: money(values.median)),
             FinancialInsightFact(id: "\(id)P90", label: "\(prefix)P90 deadline balance", value: money(values.upper))]
        }

        var facts = [
            FinancialInsightFact(id: "target", label: "Goal target", value: money(target)),
            FinancialInsightFact(id: "deadline", label: "Deadline", value: formatted(inputs.targetDate)),
            FinancialInsightFact(id: "paths", label: "Simulated paths", value: paths)
        ]
        let prefix = snapshot.includesPurchase ? "Without the purchase: " : ""
        if let cost = snapshot.context.purchase?.amountMinor {
            facts.append(FinancialInsightFact(id: "cost", label: "Purchase cost (one-off)", value: money(cost)))
        }
        // Labelled as a share of paths so the model does not read it as a projection or a balance.
        let share = "(share of simulated paths that reach the target)"
        facts.append(FinancialInsightFact(id: "baselineSuccess",
                                          label: snapshot.includesPurchase ? "Success without the purchase \(share)" : "Estimated success \(share)",
                                          value: success(snapshot.baselinePercentage, snapshot.baselineSuccessCount)))
        if let purchasePercentage = snapshot.purchasePercentage, let purchaseCount = snapshot.purchaseSuccessCount {
            facts.append(FinancialInsightFact(id: "purchaseSuccess", label: "Success with the purchase \(share)",
                                              value: success(purchasePercentage, purchaseCount)))
        }
        if let reduction = snapshot.reductionPercentagePoints {
            facts.append(FinancialInsightFact(id: "reduction", label: "Change with the purchase", value: reductionText(reduction)))
        }
        facts += percentiles(prefix, "baseline", snapshot.baselineDeadline)
        if let purchaseDeadline = snapshot.purchaseDeadline {
            facts += percentiles("With the purchase: ", "purchase", purchaseDeadline)
        }
        let single = "(one projection, not a simulated estimate)"
        facts.append(FinancialInsightFact(id: "deterministicBaseline", label: "\(prefix)deadline balance if income and expenses stay as entered \(single)",
                                          value: money(snapshot.deterministicBaselineMinor)))
        if let deterministicPurchase = snapshot.deterministicPurchaseMinor {
            facts.append(FinancialInsightFact(id: "deterministicPurchase", label: "With the purchase: deadline balance if income and expenses stay as entered \(single)",
                                              value: money(deterministicPurchase)))
        }
        facts.append(FinancialInsightFact(id: "deposits", label: "Number of monthly deposits before the deadline", value: "\(snapshot.depositMonths)"))
        facts.append(FinancialInsightFact(id: "incomeVariability", label: "Income variability",
                                          value: "up to \(snapshot.incomeVariability)% either way each month"))
        facts.append(FinancialInsightFact(id: "expenseVariability", label: "Expense variability",
                                          value: "up to \(snapshot.expenseVariability)% either way each month"))

        var relationships: [String] = []
        if let purchaseDeadline = snapshot.purchaseDeadline,
           let before = magnitude(of: snapshot.baselineDeadline.median, minus: target),
           let after = magnitude(of: purchaseDeadline.median, minus: target) {
            // One "from ... to ..." sentence; two separate median sentences were confused by the model.
            // The shift itself is stated so the model never subtracts the two medians.
            let shift = magnitude(of: snapshot.baselineDeadline.median, minus: purchaseDeadline.median)
                .map { " by \(money($0))" } ?? ""
            relationships.append("The purchase lowers the median simulated deadline balance\(shift): from \(money(before)) \(snapshot.baselineDeadline.median >= target ? "above" : "below") the target without the purchase to \(money(after)) \(purchaseDeadline.median >= target ? "above" : "below") it with the purchase.")
        } else {
            relationships.append(medianRelationship("The", median: snapshot.baselineDeadline.median, target: target, money: money))
        }
        if let edge = sharedEdgeOutcome(snapshot) {
            // Identical "every path" or "no path" lines for both cases were copied into both fields.
            relationships.append(edge
                ? "Every simulated path reaches the target both with and without the purchase, so the purchase does not change success."
                : "No simulated path reaches the target, with or without the purchase.")
        } else {
            // The same target position stated twice made the summary long and repetitive, so it is
            // merged when both cases have one and it matches.
            let total = snapshot.simulationCount
            let sharedPosition: String? = if let purchaseCount = snapshot.purchaseSuccessCount,
                let purchaseDeadline = snapshot.purchaseDeadline,
                (1..<total).contains(snapshot.baselineSuccessCount), (1..<total).contains(purchaseCount),
                targetPosition(target, snapshot.baselineDeadline) == targetPosition(target, purchaseDeadline) {
                targetPosition(target, purchaseDeadline)
            } else { nil }
            relationships += outcomeRelationships(prefix: snapshot.includesPurchase ? "Without the purchase, " : "",
                                                  count: snapshot.baselineSuccessCount, total: total,
                                                  percentage: snapshot.baselinePercentage, target: target,
                                                  balances: snapshot.baselineDeadline, includePosition: sharedPosition == nil)
            if let purchaseCount = snapshot.purchaseSuccessCount, let purchaseDeadline = snapshot.purchaseDeadline,
               let purchasePercentage = snapshot.purchasePercentage {
                relationships += outcomeRelationships(prefix: "With the purchase, ", count: purchaseCount, total: total,
                                                      percentage: purchasePercentage, target: target, balances: purchaseDeadline,
                                                      includePosition: sharedPosition == nil)
            }
            if let sharedPosition {
                relationships.append("Both with and without the purchase, \(sharedPosition)")
            }
        }
        if snapshot.depositMonths == 0 {
            relationships.append("No monthly deposit occurs before the deadline, so variability has no effect; the result depends only on starting savings.")
        } else if snapshot.incomeVariability == 0, snapshot.expenseVariability == 0 {
            relationships.append("Variability is zero, so every simulated path is identical and matches the unchanged-amount balance.")
        }

        return FinancialInsightRequest(
            context: context, title: "This forecast",
            status: snapshot.includesPurchase
                ? "Success without the purchase: \(snapshot.baselinePercentage)%. With the purchase: \(snapshot.purchasePercentage ?? 0)%."
                : "Estimated success: \(snapshot.baselinePercentage)%.",
            facts: facts, relationships: relationships,
            rules: [
                "Success means a simulated balance reaches the target on the deadline; it describes the goal, not the purchase.",
                "A purchase is a one-off cost applied once to the same simulated paths; it does not change monthly income, expenses or capacity.",
                "A success percentage is a share of simulated paths, not a projection. The balance if income and expenses stay as entered is a single separate projection.",
                "P10, P50 and P90 are simulated deadline balances, not probabilities, and P10 and P90 are not worst or best cases.",
                "These are simulated estimates under the chosen variability, not predictions."
            ],
            focus: forecastFocus(snapshot),
            considerationFocus: forecastConsiderationFocus(snapshot),
            suggestions: forecastSuggestions(snapshot),
            uncertaintyNote: "Simulated estimates under your chosen variability. Percentages are rounded, and P10 and P90 are lower and higher simulated balances, not worst or best cases."
        )
    }

    // true when every path succeeds in both cases, false when none does; nil otherwise.
    private static func sharedEdgeOutcome(_ snapshot: ForecastInsightSnapshot) -> Bool? {
        guard let purchaseCount = snapshot.purchaseSuccessCount, purchaseCount == snapshot.baselineSuccessCount else { return nil }
        if purchaseCount == snapshot.simulationCount { return true }
        if purchaseCount == 0 { return false }
        return nil
    }

    // When the purchase does not change how many paths succeed, there is no success difference
    // to explain; the summary covers what the cost does to the balances instead.
    private static func forecastFocus(_ snapshot: ForecastInsightSnapshot) -> String {
        // "In terms of simulated paths": an open question drew "you are projected to fail", which
        // presents a share of paths as a single projection.
        guard let purchaseCount = snapshot.purchaseSuccessCount else {
            return "Explain, in terms of simulated paths rather than a projection, what the success estimate means and how the spread of simulated deadline balances relates to the target."
        }
        if purchaseCount == snapshot.baselineSuccessCount {
            return "Explain the trade-off: the purchase lowers the simulated deadline balances without changing how many paths reach the target, and what its cost does to the margin between the median balance and the target."
        }
        return "Explain, in terms of simulated paths rather than a projection, what the difference in success means, why the purchase has this effect on the simulated deadline balances, and how the spread of balances relates to the target."
    }

    private static func forecastConsiderationFocus(_ snapshot: ForecastInsightSnapshot) -> String {
        if snapshot.depositMonths == 0 {
            return "why only starting savings matter when no monthly deposit occurs before the deadline."
        }
        if snapshot.incomeVariability == 0, snapshot.expenseVariability == 0 {
            return "why zero variability means every simulated path is identical, so this result only shows what happens if income and expenses stay exactly as entered."
        }
        // The summary already covers the median margin, so the key point is what the result rests on.
        // A forecast without a purchase whose paths all succeed or all fall short is treated the same way;
        // asking about sensitivity there made the model repeat its summary's variability sentence.
        let baselineEdge: Bool? = snapshot.includesPurchase ? nil
            : snapshot.baselineSuccessCount == snapshot.simulationCount ? true
            : snapshot.baselineSuccessCount == 0 ? false : nil
        if let edge = sharedEdgeOutcome(snapshot) ?? baselineEdge {
            let range = "the simulated paths only vary income by up to \(snapshot.incomeVariability)% and expenses by up to \(snapshot.expenseVariability)% each month, so larger changes are not covered."
            return edge
                ? "why every simulated path reaching the target is not a promise: \(range)"
                : "what this result depends on: \(range)"
        }
        // The summary's relationship already states the median gap with the purchase; asking for it
        // again here led the model to repeat that sentence in both fields.
        if snapshot.includesPurchase {
            return "how the chosen variability of up to \(snapshot.incomeVariability)% for income and \(snapshot.expenseVariability)% for expenses shapes the change in success with the purchase."
        }
        return "how sensitive this estimate is to the chosen variability of up to \(snapshot.incomeVariability)% for income and \(snapshot.expenseVariability)% for expenses."
    }

    private static func medianRelationship(_ subject: String, median: Int64, target: Int64, money: (Int64) -> String) -> String {
        guard let margin = magnitude(of: median, minus: target) else { return "\(subject) median simulated deadline balance is compared with the target." }
        return median >= target
            ? "\(subject) median simulated deadline balance is \(money(margin)) above the target."
            : "\(subject) median simulated deadline balance is \(money(margin)) below the target."
    }

    // Exact counts at the edges and for rounded displays; otherwise the target's position among
    // the engine's own P10/P50/P90 balances (nearest-rank), with no new threshold.
    private static func outcomeRelationships(prefix: String, count: Int, total: Int, percentage: Int,
                                             target: Int64, balances: ForecastPercentiles,
                                             includePosition: Bool = true) -> [String] {
        if count == total { return [prefix.isEmpty ? "Every simulated path reaches the target." : prefix + "every simulated path reaches the target."] }
        if count == 0 { return [prefix.isEmpty ? "No simulated path reaches the target." : prefix + "no simulated path reaches the target."] }
        var lines: [String] = []
        if percentage == 100 || percentage == 0 {
            lines.append(prefix.isEmpty
                ? "The displayed \(percentage)% is rounded: \(count.formatted()) of \(total.formatted()) paths reach the target."
                : prefix + "the displayed \(percentage)% is rounded: \(count.formatted()) of \(total.formatted()) paths reach the target.")
        }
        if includePosition {
            let position = targetPosition(target, balances)
            lines.append(prefix.isEmpty ? capitalized(position) : prefix + position)
        }
        return lines
    }

    private static func targetPosition(_ target: Int64, _ balances: ForecastPercentiles) -> String {
        if target <= balances.lower {
            "the target is at or below the P10 balance, so most simulated paths reach it."
        } else if target <= balances.median {
            "the target is between the P10 and median balances, so about half or more of the simulated paths reach it."
        } else if target <= balances.upper {
            "the target is between the median and P90 balances, so fewer than half of the simulated paths reach it."
        } else {
            "the target is above the P90 balance, so few simulated paths reach it."
        }
    }

    private static func forecastSuggestions(_ snapshot: ForecastInsightSnapshot) -> [FinancialInsightSuggestion] {
        let money = moneyFormatter(snapshot.context.currencyCode)
        let target = snapshot.context.inputs.targetMinor
        let assumptions = FinancialInsightSuggestion(step: .reviewForecastAssumptions,
            text: "Adjust Assumptions and rerun with different variability to see how sensitive this result is.")
        if snapshot.depositMonths == 0 {
            return [FinancialInsightSuggestion(step: .reviewGoal,
                text: "Review this goal's deadline. No monthly deposit occurs before it, so only current savings count and variability cannot change the result.")]
        }
        if let purchaseCount = snapshot.purchaseSuccessCount, purchaseCount < snapshot.baselineSuccessCount,
           let reduction = snapshot.reductionPercentagePoints {
            return [FinancialInsightSuggestion(step: .compareSmallerPurchase,
                text: "Return to the purchase, try a smaller amount, and forecast again. With this amount, success is \(reductionText(reduction))."), assumptions]
        }
        if snapshot.incomeVariability == 0, snapshot.expenseVariability == 0 {
            return [FinancialInsightSuggestion(step: .reviewForecastAssumptions,
                text: "Adjust Assumptions to add income or expense variability. At 0% every path is identical, so this forecast shows no uncertainty.")]
        }
        // The target sits above the P10 balance, so a meaningful share of paths fall short.
        if target > snapshot.baselineDeadline.lower {
            return [FinancialInsightSuggestion(step: .reviewGoal,
                text: "Review this goal's deadline or target. The \(money(target)) target is above the P10 balance of \(money(snapshot.baselineDeadline.lower)), so a meaningful share of simulated paths fall short."), assumptions]
        }
        return [FinancialInsightSuggestion(step: .reviewForecastAssumptions,
            text: "Adjust Assumptions and try higher variability to test how well this result holds up in less predictable months.")]
    }

    //Shared app-authored text

    static func statusText(_ status: GoalFundingStatus) -> String {
        switch status {
        case .fundedNow:
            "Funded now: savings already meet the target and are projected to stay above it at the deadline"
        case .onTrack:
            "On track: projected to reach the target by the deadline"
        case .atRisk(nil, _, _):
            "At risk: funded now, but the projected balance falls below the target by the deadline"
        case .atRisk:
            "At risk: projected to reach the target after the deadline"
        case .noContributionBeforeDeadline:
            "At risk: no monthly deposit occurs before the deadline, and current savings are below the target"
        case .pastDeadline:
            "Past deadline: the deadline has already passed"
        case .nonpositiveCapacity:
            "No savings capacity: monthly capacity is zero or negative, so savings are not projected to reach the target"
        case .completionBeyondLimit:
            "At risk: completion is beyond the 1,200-month projection limit"
        case .invalidInputs:
            "Invalid inputs"
        case .overflow:
            "Calculation overflow"
        }
    }

    static func completionText(_ projection: GoalCompletionProjection) -> String {
        switch projection {
        case .completedNow:
            "Target already reached with current savings"
        case .projected(let months, let date):
            "In \(months) \(months == 1 ? "month" : "months") · \(formatted(date))"
        case .noPositiveSavingsCapacity:
            "Unavailable: no positive monthly savings capacity"
        case .beyondLimit:
            "Unavailable: beyond the 1,200-month projection limit"
        }
    }

    // Floor rather than round so an unfunded goal never displays as 100%.
    static func progressText(_ progress: Double) -> String {
        guard progress.isFinite else { return "Unavailable" }
        return "\(Int((min(max(progress, 0), 1) * 100).rounded(.down)))%"
    }

    static func reductionText(_ points: Int) -> String {
        if points == 0 { return "no change in rounded success" }
        let unit = abs(points) == 1 ? "percentage point" : "percentage points"
        return points > 0 ? "\(points) \(unit) lower" : "\(-points) \(unit) higher"
    }

    private static func capitalized(_ sentence: String) -> String {
        sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    // Checked |a - b| for presenting a relationship between two existing results; nil on overflow.
    private static func magnitude(of a: Int64, minus b: Int64) -> Int64? {
        let difference = a.subtractingReportingOverflow(b)
        guard !difference.overflow else { return nil }
        return Int64(exactly: difference.partialValue.magnitude)
    }

    private static func metricText(_ metric: PurchaseImpactMetric, currencyCode: String) -> String {
        switch metric {
        case .months(let months):
            "\(months) \(months == 1 ? "month" : "months")"
        case .amount(let amount):
            MoneyFormatting.display(amount, currencyCode: currencyCode)
        case .unavailable(let reason):
            unavailableText(reason)
        }
    }

    private static func unavailableText(_ reason: PurchaseImpactUnavailableReason) -> String {
        switch reason {
        case .currentPlanAlreadyMissesDeadline: "Unavailable: current plan already falls short"
        case .pastDeadline: "Unavailable: deadline is in the past"
        case .noDepositsBeforeDeadline: "Unavailable: no monthly deposit occurs before the deadline"
        case .noPositiveSavingsCapacity: "Unavailable: no positive monthly savings capacity"
        case .projectionBeyondLimit: "Unavailable: beyond the 1,200-month projection limit"
        case .arithmeticOverflow: "Unavailable: numbers are too large"
        case .notNeeded: "Unavailable"
        }
    }

    private static func moneyFormatter(_ currencyCode: String) -> (Int64) -> String {
        { MoneyFormatting.display($0, currencyCode: currencyCode) }
    }

    private static func formatted(_ date: Date) -> String {
        FinancialCalendar.displayDate(fromUTCNoon: date)
            .formatted(.dateTime.day().month(.abbreviated).year())
    }
}
