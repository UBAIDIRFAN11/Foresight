import Foundation
import SwiftData

@MainActor
enum SavedDecisionStore {
    static func save(_ evaluation: PurchaseImpactEvaluation, in context: ModelContext) throws -> SavedDecision {
        let id = evaluation.id
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
            context.rollback()
            throw error
        }
    }
}
