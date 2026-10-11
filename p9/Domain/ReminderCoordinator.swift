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

    private let notificationClient: NotificationClient
    private var isReconciling = false
    private var needsAnotherRun = false

    init(notificationClient: NotificationClient) {
        self.notificationClient = notificationClient
    }

    func reconcile(
        in context: ModelContext,
        globallyPaused: Bool,
        requestAuthorizationIfNeeded: Bool = false
    ) {
        Task { @MainActor in
            await reconcileNow(
                in: context,
                globallyPaused: globallyPaused,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            )
        }
    }

    func openSystemSettings() {
        notificationClient.openSettings()
    }

    private func reconcileNow(
        in context: ModelContext,
        globallyPaused: Bool,
        requestAuthorizationIfNeeded: Bool
    ) async {
        if isReconciling {
            needsAnotherRun = true
            return
        }

        isReconciling = true
        repeat {
            needsAnotherRun = false
            await runReconciliation(
                in: context,
                globallyPaused: globallyPaused,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            )
        } while needsAnotherRun
        isReconciling = false
    }

    private func runReconciliation(
        in context: ModelContext,
        globallyPaused: Bool,
        requestAuthorizationIfNeeded: Bool
    ) async {
        deliverySettings = await notificationClient.deliverySettings()
        if requestAuthorizationIfNeeded, deliverySettings.permissionState == .notDetermined {
            do {
                _ = try await notificationClient.requestAuthorization()
                deliverySettings = await notificationClient.deliverySettings()
            } catch {
                schedulingError = "Could not request notification permission. \(error.localizedDescription)"
                return
            }
        }

        do {
            let records = try context.fetch(FetchDescriptor<ReminderRecord>())
            let decisions = try context.fetch(FetchDescriptor<SavedDecision>())
            let goals = try context.fetch(FetchDescriptor<FinancialGoal>())

            let decisionIDs = Set(decisions.map(\.evaluationID))
            let goalIDs = Set(goals.map(\.id))
            let snapshots = records.map { record in
                ReminderSnapshot(
                    record: record,
                    title: title(for: record, decisions: decisions, goals: goals),
                    body: body(for: record, decisions: decisions, goals: goals)
                )
            }

            let planner = ReminderPlanner()
            let planned = try planner.plan(
                snapshots: snapshots,
                validGoalIDs: goalIDs,
                validSavedDecisionIDs: decisionIDs,
                globallyPaused: globallyPaused
            )

            let pending = Set(await notificationClient.pendingRequests())
            let namespacePending = pending.filter { $0.hasPrefix(ReminderNotificationConstants.namespacePrefix) }
            let plannedIDs = Set(planned.map(\.requestIdentifier))
            let removeIDs = Array(namespacePending.subtracting(plannedIDs))
            if !removeIDs.isEmpty {
                await notificationClient.remove(requestIdentifiers: removeIDs)
            }

            guard deliverySettings.permissionState.allowsScheduling else {
                scheduledRequestIDs = []
                schedulingError = deliverySettings.permissionState == .denied ? "Notification permission is denied. Your reminder settings are saved." : nil
                return
            }

            for reminder in planned {
                await notificationClient.remove(requestIdentifiers: [reminder.requestIdentifier])
                try await notificationClient.schedule(reminder)
            }
            scheduledRequestIDs = plannedIDs
            schedulingError = nil
        } catch {
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
