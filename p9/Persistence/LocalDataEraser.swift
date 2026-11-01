import Foundation
import SwiftData

/// Deletes every app model in one context/save. The caller first removes views
/// holding models and waits for reminder work to stop.
@MainActor
struct LocalDataEraser {
    var save: (ModelContext) throws -> Void = { try $0.save() }

    func erase(in context: ModelContext) throws {
        do {
            // Fetch before deleting so a fetch failure cannot leave a partial draft.
            let profiles = try context.fetch(FetchDescriptor<FinancialProfile>())
            let goals = try context.fetch(FetchDescriptor<FinancialGoal>())
            let decisions = try context.fetch(FetchDescriptor<SavedDecision>())
            let reminders = try context.fetch(FetchDescriptor<ReminderRecord>())
            for record in reminders { context.delete(record) }
            for decision in decisions { context.delete(decision) }
            for goal in goals { context.delete(goal) }
            for profile in profiles { context.delete(profile) }
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

/// NotificationCenter is app-scoped. Enumerate all identifiers, including
/// one-offs and legacy identifiers, then verify both queues are empty.
@MainActor
struct LocalNotificationCleaner {
    let client: any NotificationClient

    func removeAllAndVerify() async -> Bool {
        // The system removal APIs don't throw. A nonempty read-back is treated
        // as incomplete cleanup; a bounded second attempt allows propagation.
        for _ in 0..<2 {
            let pending = await client.pendingRequests()
            let delivered = await client.deliveredRequests()
            await client.removePending(requestIdentifiers: pending)
            await client.removeDelivered(requestIdentifiers: delivered)
            let remainingPending = await client.pendingRequests()
            let remainingDelivered = await client.deliveredRequests()
            if remainingPending.isEmpty && remainingDelivered.isEmpty { return true }
        }
        return false
    }
}
