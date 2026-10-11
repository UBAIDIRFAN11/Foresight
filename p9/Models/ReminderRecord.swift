// SwiftData model for reminder intent. Notifications are derived from these
// records so saved configuration survives permission changes and app relaunches.
import Foundation
import SwiftData

@Model
final class ReminderRecord {
    @Attribute(.unique) var requestIdentifier: String
    var kindRawValue: String
    var sourceID: UUID
    var isEnabled: Bool
    var deliveryDate: Date?
    var weekday: Int
    var hour: Int
    var minute: Int
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
