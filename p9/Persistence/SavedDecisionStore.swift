import Foundation
import SwiftData

//helper for saving a completed purchase simulation into History
//This file takes the result of PurchaseImpactEvaluation and permanently saves it as a SavedDecision using SwiftData.

@MainActor
enum SavedDecisionStore {
    static func saveLive(
        _ evaluation: PurchaseImpactEvaluation, in context: ModelContext,
        now: Date = Date(), calendar: Calendar = .current
    ) throws -> SavedDecision {
        try validateLive(evaluation, in: context, now: now, calendar: calendar)
        return try save(evaluation, in: context)
    }

    static func validateLive(
        _ evaluation: PurchaseImpactEvaluation, in context: ModelContext,
        now: Date = Date(), calendar: Calendar = .current
    ) throws {
        let profiles = try FinancialProfilePolicy.fetchProfiles(in: context)
        let goals = try context.fetch(FetchDescriptor<FinancialGoal>())
        guard let profile = FinancialProfilePolicy.selectedProfile(from: profiles),
              let goal = goals.first(where: { $0.id == evaluation.goalID }),
              FinancialCalendar.localEvaluationDay(for: now, calendar: calendar) == evaluation.evaluationDate,
              profile.currentSavingsMinor == evaluation.originalSavingsMinor,
              profile.monthlyIncomeMinor == evaluation.originalIncomeMinor,
              profile.recurringExpensesMinor == evaluation.originalExpensesMinor,
              profile.preferredCurrencyCode == evaluation.currencyCode,
              goal.name == evaluation.goalName,
              goal.targetAmountMinor == evaluation.goalTargetMinor,
              goal.targetDate == evaluation.goalTargetDate else {
            throw StaleEvaluationError()
        }
    }

    static func save(_ evaluation: PurchaseImpactEvaluation, in context: ModelContext) throws -> SavedDecision {
        let id = evaluation.id
        // Saving the same result twice should not create duplicate history rows.
        var descriptor = FetchDescriptor<SavedDecision>(
            predicate: #Predicate<SavedDecision> { decision in
                decision.evaluationID == id
            }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let decision = SavedDecision(evaluation: evaluation)
        context.insert(decision)
        do {
            try context.save()
            return decision
        } catch {
            // Leave the displayed result intact so the user can try saving again.
            context.rollback()
            throw error
        }
    }
}

struct StaleEvaluationError: LocalizedError {
    var errorDescription: String? {
        "The profile, goal or calendar day changed. Your result is retained; use Adjust Purchase and calculate again before saving."
    }
}
