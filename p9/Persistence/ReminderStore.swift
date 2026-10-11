// Performs reminder create/update/cancel/review writes with explicit saves and
// rollback so failed persistence never changes notification scheduling.
import Foundation
import SwiftData

@MainActor
enum ReminderStore {
    static func upsertPurchaseReminder(
        for decision: SavedDecision,
        deliveryDate: Date,
        in context: ModelContext
    ) throws -> ReminderRecord {
        guard deliveryDate > Date() else {
            throw ReminderPlanningError.expiredPurchaseReminder
        }
        try validateCapacity(enablingSourceID: decision.evaluationID, kind: .purchaseReview, in: context)
        let record = try existing(kind: .purchaseReview, sourceID: decision.evaluationID, in: context) ?? ReminderRecord(
            requestIdentifier: ReminderKind.requestIdentifier(kind: .purchaseReview, sourceID: decision.evaluationID),
            kind: .purchaseReview,
            sourceID: decision.evaluationID,
            isEnabled: true
        )
        if record.modelContext == nil {
            context.insert(record)
        }
        record.isEnabled = true
        record.deliveryDate = deliveryDate
        record.reviewedAt = nil
        record.scheduleRevision = UUID()
        record.updatedAt = Date()
        return try save(record, in: context)
    }

    static func upsertGoalReminder(
        for goal: FinancialGoal,
        weekday: Int,
        hour: Int,
        minute: Int,
        isEnabled: Bool,
        in context: ModelContext
    ) throws -> ReminderRecord {
        if isEnabled {
            try validateCapacity(enablingSourceID: goal.id, kind: .goalCheckIn, in: context)
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
        if record.modelContext == nil {
            context.insert(record)
        }
        record.isEnabled = isEnabled
        record.weekday = weekday
        record.hour = hour
        record.minute = minute
        record.scheduleRevision = UUID()
        record.updatedAt = Date()
        return try save(record, in: context)
    }

    static func cancel(_ record: ReminderRecord, in context: ModelContext) throws {
        record.isEnabled = false
        record.scheduleRevision = UUID()
        record.updatedAt = Date()
        try saveOnly(in: context)
    }

    static func markReviewed(_ record: ReminderRecord, in context: ModelContext) throws {
        record.reviewedAt = Date()
        record.isEnabled = false
        record.scheduleRevision = UUID()
        record.updatedAt = Date()
        try saveOnly(in: context)
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

    private static func save(_ record: ReminderRecord, in context: ModelContext) throws -> ReminderRecord {
        do {
            try context.save()
            return record
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func saveOnly(in context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func validateCapacity(enablingSourceID: UUID, kind: ReminderKind, in context: ModelContext) throws {
        let records = try context.fetch(FetchDescriptor<ReminderRecord>())
        let activeCount = records.filter { record in
            record.isEnabled &&
            record.reviewedAt == nil &&
            !(record.sourceID == enablingSourceID && record.kind == kind)
        }.count
        guard activeCount < ReminderPlanner.maximumScheduledReminders else {
            throw ReminderPlanningError.capacityExceeded
        }
    }
}
