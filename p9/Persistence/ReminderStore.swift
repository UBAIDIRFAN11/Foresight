// Performs reminder create/update/cancel/review writes with explicit saves and
// rollback so failed persistence never changes notification scheduling.
import Foundation
import SwiftData

@MainActor
enum ReminderStore {
    static func saveLivePurchaseReminder(
        evaluation: PurchaseImpactEvaluation, deliveryDate: Date, in context: ModelContext,
        now: Date = Date(), calendar: Calendar = .current,
        saveOperation: (() throws -> Void)? = nil
    ) throws -> SavedDecision {
        // Keep a successfully saved decision if reminder persistence fails. A retry
        // reuses its evaluation ID, while still checking freshness again.
        let decision = try SavedDecisionStore.saveLive(evaluation, in: context, now: now, calendar: calendar)
        _ = try upsertPurchaseReminder(for: decision, deliveryDate: deliveryDate, in: context,
                                      now: now, saveOperation: saveOperation)
        return decision
    }

    static func upsertPurchaseReminder(
        for decision: SavedDecision,
        deliveryDate: Date,
        in context: ModelContext,
        now: Date = Date(),
        saveOperation: (() throws -> Void)? = nil
    ) throws -> ReminderRecord {
        guard deliveryDate > now else {
            throw ReminderPlanningError.expiredPurchaseReminder
        }
        try validateCapacity(enablingSourceID: decision.evaluationID, kind: .purchaseReview, in: context, now: now)
        let record = try existing(kind: .purchaseReview, sourceID: decision.evaluationID, in: context) ?? ReminderRecord(
            requestIdentifier: ReminderKind.requestIdentifier(kind: .purchaseReview, sourceID: decision.evaluationID),
            kind: .purchaseReview,
            sourceID: decision.evaluationID,
            isEnabled: true
        )
        return try update(record, in: context, saveOperation: saveOperation) {
            $0.isEnabled = true
            $0.deliveryDate = deliveryDate
            $0.reviewedAt = nil
            $0.scheduleRevision = UUID()
            $0.updatedAt = now
        }
    }

    static func upsertGoalReminder(
        for goal: FinancialGoal,
        weekday: Int,
        hour: Int,
        minute: Int,
        isEnabled: Bool,
        in context: ModelContext,
        now: Date = Date(),
        saveOperation: (() throws -> Void)? = nil
    ) throws -> ReminderRecord {
        guard (1...7).contains(weekday), (0...23).contains(hour), (0...59).contains(minute) else {
            throw ReminderPlanningError.invalidWeeklyComponents
        }
        if isEnabled {
            try validateCapacity(enablingSourceID: goal.id, kind: .goalCheckIn, in: context, now: now)
        }
        let record = try existing(kind: .goalCheckIn, sourceID: goal.id, in: context) ?? ReminderRecord(
            requestIdentifier: ReminderKind.requestIdentifier(kind: .goalCheckIn, sourceID: goal.id),
            kind: .goalCheckIn,
            sourceID: goal.id,
            isEnabled: isEnabled,
            weekday: weekday,
            hour: hour,
            minute: minute
        )
        return try update(record, in: context, saveOperation: saveOperation) {
            $0.isEnabled = isEnabled
            $0.weekday = weekday
            $0.hour = hour
            $0.minute = minute
            $0.scheduleRevision = UUID()
            $0.updatedAt = now
        }
    }

    static func cancel(_ record: ReminderRecord, in context: ModelContext) throws {
        _ = try update(record, in: context) {
            $0.isEnabled = false
            $0.scheduleRevision = UUID()
            $0.updatedAt = Date()
        }
    }

    static func markReviewed(_ record: ReminderRecord, in context: ModelContext) throws {
        _ = try update(record, in: context) {
            $0.reviewedAt = Date()
            $0.isEnabled = false
            $0.scheduleRevision = UUID()
            $0.updatedAt = Date()
        }
    }

    static func existing(kind: ReminderKind, sourceID: UUID, in context: ModelContext) throws -> ReminderRecord? {
        let identifier = ReminderKind.requestIdentifier(kind: kind, sourceID: sourceID)
        var descriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate<ReminderRecord> { record in
                record.requestIdentifier == identifier
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func snooze(
        sourceID: UUID, revision: UUID?, in context: ModelContext, now: Date = Date(),
        calendar: Calendar = .current, saveOperation: (() throws -> Void)? = nil
    ) throws -> Bool {
        guard let revision,
              let record = try existing(kind: .purchaseReview, sourceID: sourceID, in: context),
              record.scheduleRevision == revision, record.isEnabled, !record.isReviewed else { return false }
        let decisions = try context.fetch(FetchDescriptor<SavedDecision>())
        guard decisions.contains(where: { $0.evaluationID == sourceID }),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
        try validateCapacity(enablingSourceID: sourceID, kind: .purchaseReview, in: context, now: now)
        _ = try update(record, in: context, saveOperation: saveOperation) {
            $0.deliveryDate = tomorrow
            $0.scheduleRevision = UUID()
            $0.updatedAt = now
        }
        return true
    }

    private static func update(
        _ record: ReminderRecord, in context: ModelContext, saveOperation: (() throws -> Void)? = nil,
        mutation: (ReminderRecord) -> Void
    ) throws -> ReminderRecord {
        let wasPersisted = record.modelContext != nil
        let previous = ReminderSnapshot(record: record, title: "", body: "")
        let updatedAt = record.updatedAt
        if !wasPersisted { context.insert(record) }
        mutation(record)
        do {
            if let saveOperation { try saveOperation() } else { try context.save() }
            return record
        } catch {
            context.rollback()
            if wasPersisted {
                // SwiftData rollback can leave optional values stale on mounted references.
                record.isEnabled = previous.isEnabled
                record.deliveryDate = previous.deliveryDate
                record.weekday = previous.weekday
                record.hour = previous.hour
                record.minute = previous.minute
                record.reviewedAt = previous.reviewedAt
                record.scheduleRevision = previous.scheduleRevision
                record.updatedAt = updatedAt
            }
            throw error
        }
    }

    private static func validateCapacity(
        enablingSourceID: UUID, kind: ReminderKind, in context: ModelContext, now: Date
    ) throws {
        let records = try context.fetch(FetchDescriptor<ReminderRecord>())
        let goalIDs = Set(try context.fetch(FetchDescriptor<FinancialGoal>()).map(\.id))
        let decisionIDs = Set(try context.fetch(FetchDescriptor<SavedDecision>()).map(\.evaluationID))
        let activeCount = records.filter { record in
            let sourceExists = record.kind == .goalCheckIn ? goalIDs.contains(record.sourceID) : decisionIDs.contains(record.sourceID)
            let unexpired = record.kind == .goalCheckIn || (record.deliveryDate.map { $0 > now } ?? false)
            return sourceExists && unexpired && record.isEnabled && record.reviewedAt == nil &&
                !(record.sourceID == enablingSourceID && record.kind == kind)
        }.count
        guard activeCount < ReminderPlanner.maximumScheduledReminders else {
            throw ReminderPlanningError.capacityExceeded
        }
    }
}
