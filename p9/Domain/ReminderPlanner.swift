import Foundation

//Determines which saved reminders should actually be scheduled.

//define possible errors
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

//representation of a reminder that is ready for scheduling
struct PlannedReminder: Equatable, Identifiable {
    var id: String { requestIdentifier }
    let requestIdentifier: String
    let kind: ReminderKind
    let sourceID: UUID
    let scheduleRevision: UUID
    
    //store notif title and body
    let title: String
    let body: String
    
    //store when/how notif should be delivered
    let trigger: ReminderTrigger
}

//define scheduling types
enum ReminderTrigger: Equatable {
    
    //a notif scheudled for 1 specific dt
    case oneTime(dateComponents: DateComponents)
    
    //a recurring wkly notif
    case weekly(weekday: Int, hour: Int, minute: Int, timeZone: TimeZone)
}

//groups the reminder-planning functionality
struct ReminderPlanner {
    static let maximumScheduledReminders = 60

    var now: () -> Date = Date.init
    var calendar: Calendar = .current

    //plan all reminders
    //return arr of valid planned reminders
    func plan(
        snapshots: [ReminderSnapshot],
        validGoalIDs: Set<UUID>,
        validSavedDecisionIDs: Set<UUID>,
        globallyPaused: Bool
    ) throws -> [PlannedReminder] {
        
        //return empty arr when reminders are globally paused
        guard !globallyPaused else { return [] }

        //exclude nil results (whihc correspond to invalid reminders)
        //check and prepare each individual reminder.
        let planned = try snapshots.compactMap { snapshot -> PlannedReminder? in
            try plan(snapshot: snapshot, validGoalIDs: validGoalIDs, validSavedDecisionIDs: validSavedDecisionIDs)
        }

        guard planned.count <= Self.maximumScheduledReminders else {
            throw ReminderPlanningError.capacityExceeded
        }
        
        //return all reminders that passed the checks (valid)
        return planned
    }

    //Checks one reminder and returns a PlannedReminder if valid, or nil if it should be skipped.
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
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
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
