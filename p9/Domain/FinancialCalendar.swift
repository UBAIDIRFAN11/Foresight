import Foundation

nonisolated enum FinancialCalendar {
    static let utcTimeZone = TimeZone(secondsFromGMT: 0)!

    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
        return calendar
    }

    static func utcNoon(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = gregorianUTC
        components.timeZone = utcTimeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return gregorianUTC.date(from: components)!
    }

    static func utcNoon(for date: Date, in calendar: Calendar = .current) -> Date {
        let local = calendar.dateComponents([.year, .month, .day], from: date)
        return utcNoon(year: local.year!, month: local.month!, day: local.day!)
    }

    static func localEvaluationDay(for date: Date = Date(), calendar: Calendar = .current) -> Date {
        utcNoon(for: date, in: calendar)
    }

    static func displayDate(fromUTCNoon date: Date, in calendar: Calendar = .current) -> Date {
        let components = gregorianUTC.dateComponents([.year, .month, .day], from: date)
        var localComponents = DateComponents()
        localComponents.calendar = calendar
        localComponents.timeZone = calendar.timeZone
        localComponents.year = components.year
        localComponents.month = components.month
        localComponents.day = components.day
        localComponents.hour = 12
        return calendar.date(from: localComponents) ?? date
    }

    static func monthsWithDeposits(from evaluationDate: Date, through targetDate: Date) -> Int {
        let evaluation = civilComponents(evaluationDate)
        let target = civilComponents(targetDate)
        let rawMonths = ((target.year! - evaluation.year!) * 12) + (target.month! - evaluation.month!)
        guard rawMonths > 0 else { return 0 }
        let anniversary = clampedAnniversary(from: evaluationDate, addingMonths: rawMonths)
        return anniversary <= targetDate ? rawMonths : max(rawMonths - 1, 0)
    }

    static func clampedAnniversary(from date: Date, addingMonths months: Int) -> Date {
        let components = civilComponents(date)
        let baseDay = components.day!
        var target = DateComponents()
        target.calendar = gregorianUTC
        target.timeZone = utcTimeZone
        target.year = components.year
        target.month = components.month! + months
        target.day = 1
        target.hour = 12
        let firstOfMonth = gregorianUTC.date(from: target)!
        let range = gregorianUTC.range(of: .day, in: .month, for: firstOfMonth)!
        target.day = min(baseDay, range.count)
        return gregorianUTC.date(from: target)!
    }

    static func civilComponents(_ date: Date) -> DateComponents {
        gregorianUTC.dateComponents([.year, .month, .day], from: utcNoon(for: date, in: gregorianUTC))
    }

    static func isBeforeDay(_ lhs: Date, _ rhs: Date) -> Bool {
        utcNoon(for: lhs, in: gregorianUTC) < utcNoon(for: rhs, in: gregorianUTC)
    }
}
