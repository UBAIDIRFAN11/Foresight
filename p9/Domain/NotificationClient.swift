// Wraps UserNotifications behind a small protocol so permission state,
// scheduling, cancellation, and Settings access stay testable and replaceable.
import Foundation
import UserNotifications
import UIKit

enum NotificationPermissionState: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case other

    var allowsScheduling: Bool {
        self == .authorized || self == .provisional
    }

    var displayText: String {
        switch self {
        case .notDetermined: "Not requested"
        case .denied: "Blocked in iOS Settings"
        case .authorized: "Allowed"
        case .provisional: "Quiet delivery"
        case .other: "Limited"
        }
    }
}

struct NotificationDeliverySettings: Equatable {
    let permissionState: NotificationPermissionState
    let alertsEnabled: Bool
    let soundEnabled: Bool
    let notificationCenterEnabled: Bool

    var summary: String {
        if permissionState == .denied {
            return "Notifications are blocked. Open iOS Settings to allow reminders."
        }
        if permissionState == .provisional {
            return "Reminders can be delivered quietly."
        }
        if permissionState.allowsScheduling, !alertsEnabled {
            return "Reminders are scheduled, but banners are off in iOS Settings."
        }
        return permissionState.displayText
    }
}

protocol NotificationClient {
    func deliverySettings() async -> NotificationDeliverySettings
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [String]
    func schedule(_ reminder: PlannedReminder) async throws
    func deliveredRequests() async -> [String]
    func removePending(requestIdentifiers: [String]) async
    func removeDelivered(requestIdentifiers: [String]) async
    func openSettings()
}

struct SystemNotificationClient: NotificationClient {
    private let center = UNUserNotificationCenter.current()

    func deliverySettings() async -> NotificationDeliverySettings {
        let settings = await center.notificationSettings()
        let state: NotificationPermissionState
        switch settings.authorizationStatus {
        case .notDetermined:
            state = .notDetermined
        case .denied:
            state = .denied
        case .authorized:
            state = .authorized
        case .provisional:
            state = .provisional
        default:
            state = .other
        }

        return NotificationDeliverySettings(
            permissionState: state,
            alertsEnabled: settings.alertSetting == .enabled,
            soundEnabled: settings.soundSetting == .enabled,
            notificationCenterEnabled: settings.notificationCenterSetting == .enabled
        )
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pendingRequests() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func schedule(_ reminder: PlannedReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = reminder.kind == .purchaseReview ? ReminderNotificationConstants.purchaseCategoryIdentifier : ReminderNotificationConstants.goalCategoryIdentifier
        content.userInfo = [
            ReminderNotificationConstants.kindKey: reminder.kind.rawValue,
            ReminderNotificationConstants.sourceIDKey: reminder.sourceID.uuidString,
            ReminderNotificationConstants.revisionKey: reminder.scheduleRevision.uuidString
        ]

        let trigger: UNNotificationTrigger
        switch reminder.trigger {
        case .oneTime(let dateComponents):
            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        case .weekly(let weekday, let hour, let minute, let timeZone):
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = timeZone
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }

        let request = UNNotificationRequest(identifier: reminder.requestIdentifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    func deliveredRequests() async -> [String] {
        await center.deliveredNotifications().map { $0.request.identifier }
    }

    func removePending(requestIdentifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
    }

    func removeDelivered(requestIdentifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

enum ReminderNotificationConstants {
    static let namespacePrefix = "foresight.reminder."
    static let purchaseCategoryIdentifier = "FORESIGHT_PURCHASE_REMINDER"
    static let goalCategoryIdentifier = "FORESIGHT_GOAL_REMINDER"
    static let remindTomorrowAction = "FORESIGHT_REMIND_TOMORROW"
    static let kindKey = "kind"
    static let sourceIDKey = "sourceID"
    static let revisionKey = "scheduleRevision"
}
