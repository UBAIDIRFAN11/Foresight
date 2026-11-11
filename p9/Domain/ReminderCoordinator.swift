import Foundation
import Combine
import SwiftData

//this is used to keep the saved SwiftData reminders and actual iOS notifications synchronised.
//It acts as the bridge between SwiftData and IOS notifications

@MainActor
final class ReminderCoordinator: ObservableObject {
    
    //store device's notif settings
    @Published private(set) var deliverySettings = NotificationDeliverySettings(
        permissionState: .notDetermined,
        alertsEnabled: false,
        soundEnabled: false,
        notificationCenterEnabled: false
    )
    
    //store an error message if notification scheduling fails. nil means no recorded error.
    @Published private(set) var schedulingError: String?
    
    //store the identifiers of notifications confirmed as pending in iOS.
    @Published private(set) var scheduledRequestIDs: Set<String> = []
    
    //store identifiers of reminders whose planning or scheduling failed.
    @Published private(set) var failedRequestIDs: Set<String> = []

    //the interface used to interact with the IOS notif system
    private let notificationClient: NotificationClient
    private let now: () -> Date
    private let calendar: () -> Calendar
    
    //store most recent synced request
    private var latestRequest: (context: ModelContext, paused: Bool)?
    private var authorizationRequested = false
    private var generation = 0
    private var worker: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(
        notificationClient: NotificationClient,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .current }
    ) {
        self.notificationClient = notificationClient
        self.now = now
        self.calendar = calendar
    }

    private(set) var isSuspendedForErasure = false

    //used to prepare for deleting app data
    func suspendForErasure() async {
        isSuspendedForErasure = true
        generation += 1
        
        //clear most recent queued sync request
        latestRequest = nil
        authorizationRequested = false
        await worker?.value
        
        //clear coordinator's tracked scheudling status and errors
        scheduledRequestIDs = []
        failedRequestIDs = []
        schedulingError = nil
    }

    //allow notif sync to run again after the erase operation
    func resumeAfterErasure() {
        isSuspendedForErasure = false
    }

    //request notif synchronisation
    ///Reconcilation means comparing what should be scheduled with what iOS actually has scheduled, then correcting any differences.
    func reconcile(
        in context: ModelContext,
        globallyPaused: Bool,
        requestAuthorizationIfNeeded: Bool = false
    ) {
        //queue a sync request
        enqueue(context: context, paused: globallyPaused, authorize: requestAuthorizationIfNeeded)
    }

    //sync and wait for completion
    func reconcileAndWait(in context: ModelContext, globallyPaused: Bool, requestAuthorizationIfNeeded: Bool = false) async {
        guard !isSuspendedForErasure else { return }
        
        //wait until continuation is resumed
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            enqueue(context: context, paused: globallyPaused, authorize: requestAuthorizationIfNeeded)
        }
    }

    //used to manage the synchronisation queue
    private func enqueue(context: ModelContext, paused: Bool, authorize: Bool) {
        guard !isSuspendedForErasure else { return }
        latestRequest = (context, paused)
        authorizationRequested = authorizationRequested || authorize
        generation += 1
        guard worker == nil else { return }
        worker = Task { @MainActor in
            while let request = latestRequest {
                let pass = generation
                await runReconciliation(in: request.context, globallyPaused: request.paused, generation: pass)
                if pass == generation { break }
            }
            worker = nil
            let completed = waiters
            waiters.removeAll()
            for continuation in completed { continuation.resume() }
        }
    }

    func openSystemSettings() {
        notificationClient.openSettings()
    }

    func reportActionError(_ error: Error) {
        schedulingError = error.localizedDescription
    }

    func status(for reminder: ReminderRecord, globallyPaused: Bool) -> String {
        if reminder.isReviewed { return "Reviewed" }
        if !reminder.isEnabled { return "Off" }
        if globallyPaused { return "Paused" }
        if deliverySettings.permissionState == .denied { return "Blocked" }
        if reminder.kind == .purchaseReview, let date = reminder.deliveryDate, date <= now() { return "Review due" }
        if failedRequestIDs.contains(reminder.requestIdentifier) { return "Failed" }
        if scheduledRequestIDs.contains(reminder.requestIdentifier) { return "Scheduled" }
        return "Saved"
    }

    //used to sync stored reminders with actual IOS notifs
    private func runReconciliation(in context: ModelContext, globallyPaused: Bool, generation pass: Int) async {
        
        //get device's delivery settings
        deliverySettings = await notificationClient.deliverySettings()
        
        //stop if new sync request has arrived
        guard pass == generation else { return }
        var errors: [String] = []
        
        //if reminders aren't paused, and permission requested, process that request
        if !globallyPaused, authorizationRequested {
            authorizationRequested = false
            
            //only request permission if user hasn't already made a decision
            if deliverySettings.permissionState == .notDetermined {
                
                //request permission, then get updated settings
                do {
                    _ = try await notificationClient.requestAuthorization()
                    deliverySettings = await notificationClient.deliverySettings()
                } catch { errors.append("Could not request notification permission. \(error.localizedDescription)") }
            }
        }
        guard pass == generation else { return }
        
        //fetch stored data
        do {
            let records = try context.fetch(FetchDescriptor<ReminderRecord>())
            let decisions = try context.fetch(FetchDescriptor<SavedDecision>())
            let goals = try context.fetch(FetchDescriptor<FinancialGoal>())
            let decisionIDs = Set(decisions.map(\.evaluationID))
            let goalIDs = Set(goals.map(\.id))
            
            //create the planner to determine which reminders are valid for scheduling
            let planner = ReminderPlanner(now: now, calendar: calendar())
            var planned: [PlannedReminder] = []
            var failed: Set<String> = []
            
            //if notifs aren't globally paused
            if !globallyPaused {
                
                //loop through every saved reminder record
                for record in records {
                    let snapshot = ReminderSnapshot(
                        record: record,
                        title: title(for: record, decisions: decisions, goals: goals),
                        body: body(for: record, decisions: decisions, goals: goals)
                    )
                    
                    //ask ReminderPlanner whether the reminder is valid/should be scheduled
                    do {
                        
                        if let item = try planner.plan(snapshot: snapshot, validGoalIDs: goalIDs, validSavedDecisionIDs: decisionIDs) {
                            
                            //append to planned arr if within maximum reminders limit
                            if planned.count < ReminderPlanner.maximumScheduledReminders {
                                planned.append(item)
                            } else { throw ReminderPlanningError.capacityExceeded }
                        }
                    } catch {
                        failed.insert(record.requestIdentifier)
                        errors.append(error.localizedDescription)
                    }
                }
            }
            
            //get identifiers of notifs currently pensing in IOS
            let pending = Set(await notificationClient.pendingRequests())
            guard pass == generation else { return }
            
            let ownedPending = pending.filter { $0.hasPrefix(ReminderNotificationConstants.namespacePrefix) }
            
            //collect ids of reminders that should be scheduled
            let plannedIDs = Set(planned.map(\.requestIdentifier))
            let retainedIDs = deliverySettings.permissionState.allowsScheduling ? plannedIDs.union(failed) : []
            await notificationClient.removePending(requestIdentifiers: Array(ownedPending.subtracting(retainedIDs)))

            let delivered = Set(await notificationClient.deliveredRequests())
            guard pass == generation else { return }
            // A delivered purchase stays visible until reviewed, disabled or its source disappears.
            let validDelivered = Set(records.filter {
                $0.isEnabled && !$0.isReviewed &&
                ($0.kind == .purchaseReview ? decisionIDs.contains($0.sourceID) : goalIDs.contains($0.sourceID))
            }.map(\.requestIdentifier))
            await notificationClient.removeDelivered(requestIdentifiers: Array(delivered.filter {
                $0.hasPrefix(ReminderNotificationConstants.namespacePrefix) && !validDelivered.contains($0)
            }))

            
            //attempt scheduling if notif permission state allows it
            if deliverySettings.permissionState.allowsScheduling {
                
                //loop through every valid planned reminder
                for reminder in planned {
                    guard pass == generation else { return }
                    do {
                        //ask IOS (through notification client), to schedule a reminder
                        try await notificationClient.schedule(reminder)
                    } catch {
                        failed.insert(reminder.requestIdentifier)
                        errors.append("Could not schedule \(reminder.title). \(error.localizedDescription)")
                    }
                }
            } else if deliverySettings.permissionState == .denied {
                errors.append("Notification permission is denied. Your reminder settings are saved.")
            }
            let actualPending = Set(await notificationClient.pendingRequests())
            guard pass == generation else { return }
            failedRequestIDs = failed
            scheduledRequestIDs = deliverySettings.permissionState.allowsScheduling
                ? actualPending.intersection(plannedIDs).subtracting(failed) : []
            schedulingError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        } catch {
            scheduledRequestIDs = []
            schedulingError = error.localizedDescription
        }
    }

    private func title(for record: ReminderRecord, decisions: [SavedDecision], goals: [FinancialGoal]) -> String {
        switch record.kind {
        case .purchaseReview:
            let name = decisions.first { $0.evaluationID == record.sourceID }?.purchaseName ?? "your saved purchase"
            return "Review \(name)"
        case .goalCheckIn:
            let name = goals.first { $0.id == record.sourceID }?.name ?? "your savings goal"
            return "Check in on \(name)"
        }
    }

    private func body(for record: ReminderRecord, decisions: [SavedDecision], goals: [FinancialGoal]) -> String {
        switch record.kind {
        case .purchaseReview:
            return "Open Foresight to review the original saved impact or re-evaluate it with current details."
        case .goalCheckIn:
            return "Revisit your manually entered profile and goal plan."
        }
    }
}
