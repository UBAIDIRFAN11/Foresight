import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppDataController {
    enum Phase: Equatable {
        case ready
        case erasing
        case cleaningNotifications
        case cleanupRequired
    }

    static let cleanupKey = "eraseNotificationCleanupPending"
    private(set) var phase: Phase
    private(set) var generation = UUID()
    var notice: String?
    private let defaults: UserDefaults
    private let eraser: LocalDataEraser
    private let cleaner: LocalNotificationCleaner
    private let suspendRouting: (Bool) -> Void
    private let clearPendingRoutes: () -> Void

    init(defaults: UserDefaults = .standard, eraser: LocalDataEraser? = nil,
         notificationClient: (any NotificationClient)? = nil,
         suspendRouting: ((Bool) -> Void)? = nil, clearPendingRoutes: (() -> Void)? = nil) {
        self.defaults = defaults
        self.eraser = eraser ?? LocalDataEraser()
        self.cleaner = LocalNotificationCleaner(client: notificationClient ?? SystemNotificationClient())
        self.suspendRouting = suspendRouting ?? { NotificationRouteBridge.isSuspendedForErasure = $0 }
        self.clearPendingRoutes = clearPendingRoutes ?? { NotificationRouteBridge.clearPendingRoute() }
        phase = defaults.bool(forKey: Self.cleanupKey) ? .cleanupRequired : .ready
    }

    func erase(in context: ModelContext, coordinator: ReminderCoordinator, router: AppRouter) async {
        guard phase == .ready else { return }
        phase = .erasing
        notice = nil
        suspendRouting(true)
        // Removing the entire content subtree dismisses sheets and abandons
        // transient chart/AI/form state before persistent models are deleted.
        await Task.yield()
        await coordinator.suspendForErasure()
        router.resetAfterErasure()
        clearPendingRoutes()
        // Journal cleanup before the irreversible save, so an interrupted reset
        // still removes notifications on next launch. It never retries deletion.
        defaults.set(true, forKey: Self.cleanupKey)
        do {
            try eraser.erase(in: context)
        } catch {
            defaults.removeObject(forKey: Self.cleanupKey)
            coordinator.resumeAfterErasure()
            suspendRouting(false)
            generation = UUID()
            phase = .ready
            notice = "Your data could not be erased. No deletion was saved. Please try again."
            coordinator.reconcile(in: context, globallyPaused: defaults.bool(forKey: "remindersPaused"))
            return
        }
        defaults.removeObject(forKey: "remindersPaused")
        phase = .cleaningNotifications
        if await cleaner.removeAllAndVerify() {
            finishCleanup(coordinator: coordinator)
            notice = "All local financial data and reminders were erased. You can set up a new profile."
        } else {
            phase = .cleanupRequired
            notice = "Your local financial records were erased, but some notifications could not be cleared. Reminder scheduling is paused. Retry cleanup; erased records cannot be restored."
        }
    }

    func retryCleanup(coordinator: ReminderCoordinator) async {
        guard phase == .cleanupRequired else { return }
        phase = .cleaningNotifications
        suspendRouting(true)
        await coordinator.suspendForErasure()
        if await cleaner.removeAllAndVerify() {
            finishCleanup(coordinator: coordinator)
            notice = "Notification cleanup finished."
        } else {
            phase = .cleanupRequired
            notice = "Some notifications remain. Reminder scheduling is paused. Try Again, or disable Foresight notifications in iOS Settings while you resolve this."
        }
    }

    private func finishCleanup(coordinator: ReminderCoordinator) {
        defaults.removeObject(forKey: Self.cleanupKey)
        coordinator.resumeAfterErasure()
        clearPendingRoutes()
        suspendRouting(false)
        generation = UUID()
        phase = .ready
    }
}
