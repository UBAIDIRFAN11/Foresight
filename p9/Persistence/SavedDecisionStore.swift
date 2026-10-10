import Foundation
import SwiftData

//helper for saving a completed purchase simulation into History
//This file takes the result of PurchaseImpactEvaluation and permanently saves it as a SavedDecision using SwiftData.

@MainActor
enum SavedDecisionStore {
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
