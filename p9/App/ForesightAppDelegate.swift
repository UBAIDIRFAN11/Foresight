// Registers local notification categories and forwards notification taps/actions
// into the SwiftUI router without putting financial logic in the app delegate.
import UIKit
import UserNotifications

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
            identifier: ReminderNotificationConstants.categoryIdentifier,
            actions: [remindTomorrow],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
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
            await NotificationActionBridge.shared.enqueueRemindTomorrow(payload: payload)
            return
        }

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

actor NotificationActionBridge {
    static let shared = NotificationActionBridge()
    private var pendingPayloads: [ReminderNotificationPayload] = []

    func enqueueRemindTomorrow(payload: ReminderNotificationPayload) {
        pendingPayloads.append(payload)
    }

    func consumePendingPayloads() -> [ReminderNotificationPayload] {
        let payloads = pendingPayloads
        pendingPayloads.removeAll()
        return payloads
    }
}
