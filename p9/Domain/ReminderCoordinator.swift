// Reconciles saved reminder intent with iOS pending notifications, including
// permission state, global pause, stale cleanup, and retryable scheduling errors.
import Foundation
import Combine
import SwiftData

@MainActor
final class ReminderCoordinator: ObservableObject {
    @Published private(set) var deliverySettings = NotificationDeliverySettings(
        permissionState: .notDetermined,
        alertsEnabled: false,
        soundEnabled: false,
        notificationCenterEnabled: false
    )
    @Published private(set) var schedulingError: String?
    @Published private(set) var scheduledRequestIDs: Set<String> = []
    @Published private(set) var failedRequestIDs: Set<String> = []

    private let notificationClient: NotificationClient
    private let now: () -> Date
    private let calendar: () -> Calendar
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

    /// Invalidate snapshots and drain a possibly in-flight add before cleanup.
    /// Cancellation alone cannot guarantee that the system did not schedule it.
    func suspendForErasure() async {
        isSuspendedForErasure = true
        generation += 1
        latestRequest = nil
        authorizationRequested = false
        await worker?.value
        scheduledRequestIDs = []
        failedRequestIDs = []
        schedulingError = nil
    }

    func resumeAfterErasure() {
        isSuspendedForErasure = false
    }

    func reconcile(
        in context: ModelContext,
        globallyPaused: Bool,
        requestAuthorizationIfNeeded: Bool = false
    ) {
        enqueue(context: context, paused: globallyPaused, authorize: requestAuthorizationIfNeeded)
    }

    func reconcileAndWait(in context: ModelContext, globallyPaused: Bool, requestAuthorizationIfNeeded: Bool = false) async {
        guard !isSuspendedForErasure else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            enqueue(context: context, paused: globallyPaused, authorize: requestAuthorizationIfNeeded)
        }
    }

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

    private func runReconciliation(in context: ModelContext, globallyPaused: Bool, generation pass: Int) async {
        deliverySettings = await notificationClient.deliverySettings()
        guard pass == generation else { return }
        var errors: [String] = []
        if !globallyPaused, authorizationRequested {
            authorizationRequested = false
            if deliverySettings.permissionState == .notDetermined {
                do {
                    _ = try await notificationClient.requestAuthorization()
                    deliverySettings = await notificationClient.deliverySettings()
                } catch { errors.append("Could not request notification permission. \(error.localizedDescription)") }
            }
        }
        guard pass == generation else { return }
        do {
            let records = try context.fetch(FetchDescriptor<ReminderRecord>())
            let decisions = try context.fetch(FetchDescriptor<SavedDecision>())
            let goals = try context.fetch(FetchDescriptor<FinancialGoal>())
            let decisionIDs = Set(decisions.map(\.evaluationID))
            let goalIDs = Set(goals.map(\.id))
            let planner = ReminderPlanner(now: now, calendar: calendar())
            var planned: [PlannedReminder] = []
            var failed: Set<String> = []
            if !globallyPaused {
                for record in records {
                    let snapshot = ReminderSnapshot(
                        record: record,
                        title: title(for: record, decisions: decisions, goals: goals),
                        body: body(for: record, decisions: decisions, goals: goals)
                    )
                    do {
                        if let item = try planner.plan(snapshot: snapshot, validGoalIDs: goalIDs, validSavedDecisionIDs: decisionIDs) {
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
            let pending = Set(await notificationClient.pendingRequests())
            guard pass == generation else { return }
            let ownedPending = pending.filter { $0.hasPrefix(ReminderNotificationConstants.namespacePrefix) }
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

            if deliverySettings.permissionState.allowsScheduling {
                for reminder in planned {
                    guard pass == generation else { return }
                    do {
                        // Adding the same identifier replaces atomically; preserve the old request on failure.
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
