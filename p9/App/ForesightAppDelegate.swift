// Registers local notification categories and forwards notification taps/actions
// into the SwiftUI router without putting financial logic in the app delegate.
import UIKit
import UserNotifications
import SwiftData

final class ForesightAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let remindTomorrow = UNNotificationAction(
            identifier: ReminderNotificationConstants.remindTomorrowAction,
            title: "Remind Tomorrow",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: ReminderNotificationConstants.purchaseCategoryIdentifier,
            actions: [remindTomorrow],
            intentIdentifiers: [],
            options: []
        )
        let goalCategory = UNNotificationCategory(identifier: ReminderNotificationConstants.goalCategoryIdentifier,
                                                   actions: [], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category, goalCategory])
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let payload = ReminderNotificationPayload(userInfo: response.notification.request.content.userInfo) else {
            return
        }

        if response.actionIdentifier == ReminderNotificationConstants.remindTomorrowAction {
            await NotificationActionBridge.shared.handleRemindTomorrow(payload: payload)
            return
        }

        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run {
            NotificationRouteBridge.route(
                kind: payload.kind,
                sourceID: payload.sourceID,
                revision: payload.revision
            )
        }
    }
}

struct ReminderNotificationPayload {
    let kind: ReminderKind
    let sourceID: UUID
    let revision: UUID?

    init?(userInfo: [AnyHashable: Any]) {
        guard let kindRaw = userInfo[ReminderNotificationConstants.kindKey] as? String,
              let kind = ReminderKind(rawValue: kindRaw),
              let sourceRaw = userInfo[ReminderNotificationConstants.sourceIDKey] as? String,
              let sourceID = UUID(uuidString: sourceRaw) else {
            return nil
        }
        self.kind = kind
        self.sourceID = sourceID
        if let revisionRaw = userInfo[ReminderNotificationConstants.revisionKey] as? String {
            self.revision = UUID(uuidString: revisionRaw)
        } else {
            self.revision = nil
        }
    }
}

@MainActor
final class NotificationActionBridge {
    static let shared = NotificationActionBridge()
    private var context: ModelContext?
    private var coordinator: ReminderCoordinator?

    func configure(context: ModelContext, coordinator: ReminderCoordinator) {
        self.context = context
        self.coordinator = coordinator
    }

    func handleRemindTomorrow(
        payload: ReminderNotificationPayload, now: Date = Date(), calendar: Calendar = .current,
        globallyPaused: Bool? = nil
    ) async {
        guard payload.kind == .purchaseReview, let context, let coordinator else { return }
        do {
            if try ReminderStore.snooze(sourceID: payload.sourceID, revision: payload.revision,
                                        in: context, now: now, calendar: calendar) {
                await coordinator.reconcileAndWait(in: context,
                    globallyPaused: globallyPaused ?? UserDefaults.standard.bool(forKey: "remindersPaused"))
            }
        } catch {
            coordinator.reportActionError(error)
        }
    }
}
