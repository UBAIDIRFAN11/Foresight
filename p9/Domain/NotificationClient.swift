import Foundation
import UserNotifications
import UIKit

//Provides the interface through which the app communicates with iOS notifications.

//Represents the possible notification permission states.
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

//Stores the device's notification settings, such as whether alerts and sounds are enabled.
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

//This defines what operations a notification client must support, without implementing them
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

//the actual implementation of the notification client protocol
struct SystemNotificationClient: NotificationClient {
    
    //gives access to Apple's notif system
    private let center = UNUserNotificationCenter.current()

    func deliverySettings() async -> NotificationDeliverySettings {
        
        //get notif settings
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

    //function to request notif disp permission
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pendingRequests() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    //receives a PlannedReminder and schedules in with IOS
    func schedule(_ reminder: PlannedReminder) async throws {
        let content = UNMutableNotificationContent()
        
        //create the notif content
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
        
        //check whether reminder is one-time or weekly
        switch reminder.trigger {
        case .oneTime(let dateComponents):
            //scheudle a reminder for a specific dt, non-repeating
            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        case .weekly(let weekday, let hour, let minute, let timeZone):
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = timeZone
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            
            //schedule recurring weekly notif
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }

        //schedule the notif with IOS
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
