import Foundation
import SwiftData

//Manages saving, updating and deleting reminder records.

@MainActor
enum ReminderStore {
    //saves a live purchase decision and its reminder
    static func saveLivePurchaseReminder(
        evaluation: PurchaseImpactEvaluation, deliveryDate: Date, in context: ModelContext,
        now: Date = Date(), calendar: Calendar = .current,
        saveOperation: (() throws -> Void)? = nil
    ) throws -> SavedDecision {
        
        //save the evaluated purchase decision
        let decision = try SavedDecisionStore.saveLive(evaluation, in: context, now: now, calendar: calendar)
        
        //create/update its reminder
        _ = try upsertPurchaseReminder(for: decision, deliveryDate: deliveryDate, in: context,
                                      now: now, saveOperation: saveOperation)
        return decision
    }

    //creates or updates a purchase reminder
    static func upsertPurchaseReminder(
        for decision: SavedDecision,
        deliveryDate: Date,
        in context: ModelContext,
        now: Date = Date(),
        saveOperation: (() throws -> Void)? = nil
    ) throws -> ReminderRecord {
        
        //reject past/curr reminders
        guard deliveryDate > now else {
            throw ReminderPlanningError.expiredPurchaseReminder
        }
        
        //check if another active reminder is allowed
        try validateCapacity(enablingSourceID: decision.evaluationID, kind: .purchaseReview, in: context, now: now)
        
        //find existing reminder or create a new one
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

    
    //create or update a weekly goal check in reminder
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
        
        //validate
        guard (1...7).contains(weekday), (0...23).contains(hour), (0...59).contains(minute) else {
            throw ReminderPlanningError.invalidWeeklyComponents
        }
        
        //check reminder capacity if it's being enabled
        if isEnabled {
            try validateCapacity(enablingSourceID: goal.id, kind: .goalCheckIn, in: context, now: now)
        }
        
        //find the goal's existing reminder or create a new one with the supplied weekly settings
        let record = try existing(kind: .goalCheckIn, sourceID: goal.id, in: context) ?? ReminderRecord(
            requestIdentifier: ReminderKind.requestIdentifier(kind: .goalCheckIn, sourceID: goal.id),
            kind: .goalCheckIn,
            sourceID: goal.id,
            isEnabled: isEnabled,
            weekday: weekday,
            hour: hour,
            minute: minute
        )
        
        //Update the enabled status, weekly schedule, revision identifier and modification time, then save
        return try update(record, in: context, saveOperation: saveOperation) {
            $0.isEnabled = isEnabled
            $0.weekday = weekday
            $0.hour = hour
            $0.minute = minute
            $0.scheduleRevision = UUID()
            $0.updatedAt = now
        }
    }

    //defines a func to disable a reminder
    static func cancel(_ record: ReminderRecord, in context: ModelContext) throws {
        
        //disables reminder, changes its revision id, records the update time and saves it.
        _ = try update(record, in: context) {
            $0.isEnabled = false
            $0.scheduleRevision = UUID()
            $0.updatedAt = Date()
        }
    }

    //Defines a function to mark a reminder as reviewed.
    static func markReviewed(_ record: ReminderRecord, in context: ModelContext) throws {
        
        //record Date when reviewed
        _ = try update(record, in: context) {
            $0.reviewedAt = Date()
            $0.isEnabled = false
            $0.scheduleRevision = UUID()
            $0.updatedAt = Date()
        }
    }

    //used to find an existing reminder
    static func existing(kind: ReminderKind, sourceID: UUID, in context: ModelContext) throws -> ReminderRecord? {
        let identifier = ReminderKind.requestIdentifier(kind: kind, sourceID: sourceID)
        
        //create SwiftData query that only matches with the specific identifier
        //#predicate defines the filtering condition
        var descriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate<ReminderRecord> { record in
                record.requestIdentifier == identifier
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    //used to postpose a reminder
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

    //Defines the shared function for modifying and saving reminder records.
    private static func update(
        _ record: ReminderRecord, in context: ModelContext, saveOperation: (() throws -> Void)? = nil,
        mutation: (ReminderRecord) -> Void
    ) throws -> ReminderRecord {
        let wasPersisted = record.modelContext != nil
        
        //capture previous reminder values so they can be restored if saving fails.
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

    //Check the reminder limit
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
