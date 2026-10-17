import Foundation
import SwiftData

// SwiftData access stays on the main actor; only the copied context crosses to the engine.
@MainActor
enum ForecastSource {
    static func context(profile: FinancialProfile, goal: FinancialGoal, evaluationDay: Date,
                        purchase: ForecastPurchase? = nil) -> ForecastContext {
        ForecastContext(goalID: goal.id, goalName: goal.name, currencyCode: profile.preferredCurrencyCode,
                        inputs: FinancialInputs(savingsMinor: profile.currentSavingsMinor,
                                                incomeMinor: profile.monthlyIncomeMinor,
                                                expensesMinor: profile.recurringExpensesMinor,
                                                targetMinor: goal.targetAmountMinor,
                                                evaluationDate: evaluationDay, targetDate: goal.targetDate),
                        purchase: purchase)
    }

    static func context(evaluation: PurchaseImpactEvaluation) -> ForecastContext {
        let conversion = evaluation.conversion
        let rateDescription = conversion.map {
            "1 \($0.exchangeRate.base) = \($0.exchangeRate.rateString) \($0.exchangeRate.quote) · Rate date \(FinancialCalendar.displayDate(fromUTCNoon: $0.exchangeRate.observationDate).formatted(date: .abbreviated, time: .omitted))"
        }
        return ForecastContext(
            goalID: evaluation.goalID, goalName: evaluation.goalName, currencyCode: evaluation.currencyCode,
            inputs: FinancialInputs(savingsMinor: evaluation.originalSavingsMinor, incomeMinor: evaluation.originalIncomeMinor,
                                    expensesMinor: evaluation.originalExpensesMinor, targetMinor: evaluation.goalTargetMinor,
                                    evaluationDate: evaluation.evaluationDate, targetDate: evaluation.goalTargetDate),
            purchase: ForecastPurchase(evaluationID: evaluation.id, name: evaluation.purchaseName,
                                       amountMinor: evaluation.purchaseAmountMinor, originalAmountMinor: evaluation.originalAmountMinor,
                                       originalCurrencyCode: evaluation.originalCurrencyCode, rateDescription: rateDescription)
        )
    }

    static func validate(_ snapshot: ForecastContext, in modelContext: ModelContext,
                         now: Date = Date(), calendar: Calendar = .current) throws {
        let profiles = try FinancialProfilePolicy.fetchProfiles(in: modelContext)
        let goals = try modelContext.fetch(FetchDescriptor<FinancialGoal>())
        guard let profile = FinancialProfilePolicy.selectedProfile(from: profiles),
              let goal = goals.first(where: { $0.id == snapshot.goalID }),
              context(profile: profile, goal: goal,
                      evaluationDay: FinancialCalendar.localEvaluationDay(for: now, calendar: calendar),
                      purchase: snapshot.purchase) == snapshot else { throw ForecastError.staleSource }
    }
}
