import Foundation
import SwiftData

//This class defines how reminders are stored in SwiftData.

//it just stores what user wants schedulued, doesn't actually itself create the IOS notification.

@Model
final class ReminderRecord {
    //each reminder contains:
    
    //unique identifier for the notif
    @Attribute(.unique) var requestIdentifier: String
    
    //whether it'sa pruchase or goal reminder
    var kindRawValue: String
    
    //uuid of associated purchase or goal
    var sourceID: UUID
    
    //whther reminder is enabled or not
    var isEnabled: Bool
    
    //date for a one-time purchase reminder
    var deliveryDate: Date?
    
    //schedule for weekly goal reminder
    var weekday: Int
    var hour: Int
    var minute: Int
    
    //date when purchase reminder has been reviewed, or nil if it hasn't
    var reviewedAt: Date?
    var scheduleRevision: UUID
    var updatedAt: Date

    init(
        requestIdentifier: String,
        kind: ReminderKind,
        sourceID: UUID,
        isEnabled: Bool,
        deliveryDate: Date? = nil,
        weekday: Int = 1,
        hour: Int = 18,
        minute: Int = 0,
        reviewedAt: Date? = nil,
        scheduleRevision: UUID = UUID(),
        updatedAt: Date = Date()
    ) {
        self.requestIdentifier = requestIdentifier
        self.kindRawValue = kind.rawValue
        self.sourceID = sourceID
        self.isEnabled = isEnabled
        self.deliveryDate = deliveryDate
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.reviewedAt = reviewedAt
        self.scheduleRevision = scheduleRevision
        self.updatedAt = updatedAt
    }
}

//defines the two types of reminders
enum ReminderKind: String, Codable, CaseIterable {
    case purchaseReview
    case goalCheckIn

    var title: String {
        switch self {
        case .purchaseReview: "Purchase review"
        case .goalCheckIn: "Goal check-in"
        }
    }

    static func requestIdentifier(kind: ReminderKind, sourceID: UUID) -> String {
        switch kind {
        case .purchaseReview:
            "foresight.reminder.purchase.\(sourceID.uuidString)"
        case .goalCheckIn:
            "foresight.reminder.goal.\(sourceID.uuidString)"
        }
    }
}

extension ReminderRecord {
    var kind: ReminderKind {
        get { ReminderKind(rawValue: kindRawValue) ?? .purchaseReview }
        set { kindRawValue = newValue.rawValue }
    }

    var isReviewed: Bool {
        reviewedAt != nil
    }
}

struct ReminderSnapshot: Equatable, Identifiable {
    var id: String { requestIdentifier }
    let requestIdentifier: String
    let kind: ReminderKind
    let sourceID: UUID
    let isEnabled: Bool
    let deliveryDate: Date?
    let weekday: Int
    let hour: Int
    let minute: Int
    let reviewedAt: Date?
    let scheduleRevision: UUID
    let title: String
    let body: String

    init(
        requestIdentifier: String,
        kind: ReminderKind,
        sourceID: UUID,
        isEnabled: Bool,
        deliveryDate: Date?,
        weekday: Int,
        hour: Int,
        minute: Int,
        reviewedAt: Date?,
        scheduleRevision: UUID,
        title: String,
        body: String
    ) {
        self.requestIdentifier = requestIdentifier
        self.kind = kind
        self.sourceID = sourceID
        self.isEnabled = isEnabled
        self.deliveryDate = deliveryDate
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.reviewedAt = reviewedAt
        self.scheduleRevision = scheduleRevision
        self.title = title
        self.body = body
    }

    init(record: ReminderRecord, title: String, body: String) {
        self.requestIdentifier = record.requestIdentifier
        self.kind = record.kind
        self.sourceID = record.sourceID
        self.isEnabled = record.isEnabled
        self.deliveryDate = record.deliveryDate
        self.weekday = record.weekday
        self.hour = record.hour
        self.minute = record.minute
        self.reviewedAt = record.reviewedAt
        self.scheduleRevision = record.scheduleRevision
        self.title = title
        self.body = body
    }
}
