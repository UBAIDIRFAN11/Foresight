// Converts immutable reminder snapshots into notification plans, keeping date,
// recurrence, expiry, and capacity rules separate from SwiftData and iOS APIs.
import Foundation

enum ReminderPlanningError: LocalizedError, Equatable {
    case expiredPurchaseReminder
    case invalidWeeklyComponents
    case capacityExceeded

    var errorDescription: String? {
        switch self {
        case .expiredPurchaseReminder:
            "Choose a future date and time for this reminder."
        case .invalidWeeklyComponents:
            "Choose a valid weekday and time."
        case .capacityExceeded:
            "Foresight can keep up to 60 active reminders. Disable another reminder before adding this one."
        }
    }
}

struct PlannedReminder: Equatable, Identifiable {
    var id: String { requestIdentifier }
    let requestIdentifier: String
    let kind: ReminderKind
    let sourceID: UUID
    let scheduleRevision: UUID
    let title: String
    let body: String
    let trigger: ReminderTrigger
}

enum ReminderTrigger: Equatable {
    case oneTime(dateComponents: DateComponents)
    case weekly(weekday: Int, hour: Int, minute: Int, timeZone: TimeZone)
}

struct ReminderPlanner {
    static let maximumScheduledReminders = 60

    var now: () -> Date = Date.init
    var calendar: Calendar = .current

    func plan(
        snapshots: [ReminderSnapshot],
        validGoalIDs: Set<UUID>,
        validSavedDecisionIDs: Set<UUID>,
        globallyPaused: Bool
    ) throws -> [PlannedReminder] {
        guard !globallyPaused else { return [] }

        let planned = try snapshots.compactMap { snapshot -> PlannedReminder? in
            try plan(snapshot: snapshot, validGoalIDs: validGoalIDs, validSavedDecisionIDs: validSavedDecisionIDs)
        }

        guard planned.count <= Self.maximumScheduledReminders else {
            throw ReminderPlanningError.capacityExceeded
        }
        return planned
    }

    func plan(
        snapshot: ReminderSnapshot,
        validGoalIDs: Set<UUID>,
        validSavedDecisionIDs: Set<UUID>
    ) throws -> PlannedReminder? {
        guard snapshot.isEnabled, snapshot.reviewedAt == nil else { return nil }

        switch snapshot.kind {
        case .purchaseReview:
            guard validSavedDecisionIDs.contains(snapshot.sourceID) else { return nil }
            guard let deliveryDate = snapshot.deliveryDate else { return nil }
            guard deliveryDate > now() else { return nil }
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            let components = utcCalendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                from: deliveryDate
            )
            return PlannedReminder(
                requestIdentifier: snapshot.requestIdentifier,
                kind: snapshot.kind,
                sourceID: snapshot.sourceID,
                scheduleRevision: snapshot.scheduleRevision,
                title: snapshot.title,
                body: snapshot.body,
                trigger: .oneTime(dateComponents: components)
            )
        case .goalCheckIn:
            guard validGoalIDs.contains(snapshot.sourceID) else { return nil }
            guard (1...7).contains(snapshot.weekday),
                  (0...23).contains(snapshot.hour),
                  (0...59).contains(snapshot.minute) else {
                throw ReminderPlanningError.invalidWeeklyComponents
            }
            return PlannedReminder(
                requestIdentifier: snapshot.requestIdentifier,
                kind: snapshot.kind,
                sourceID: snapshot.sourceID,
                scheduleRevision: snapshot.scheduleRevision,
                title: snapshot.title,
                body: snapshot.body,
                trigger: .weekly(
                    weekday: snapshot.weekday,
                    hour: snapshot.hour,
                    minute: snapshot.minute,
                    timeZone: calendar.timeZone
                )
            )
        }
    }
}
