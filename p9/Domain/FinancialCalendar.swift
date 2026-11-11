import Foundation

//Keeps financial date calculations consistent across time zones and daylight saving changes.

nonisolated enum FinancialCalendar {
    static let utcTimeZone = TimeZone(secondsFromGMT: 0)!

    //create a grogorian calendar configured to use UTC
    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
        return calendar
    }

    //this function is used to represent a calendar date using 12:00 UTC
    //it takes a year, month, day, and creates a Date representing 12:00PM UTC on that day
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

    //normalise an existing Date to be in UTC noon format
    static func utcNoon(for date: Date, in calendar: Calendar = .current) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let local = gregorian.dateComponents([.year, .month, .day], from: date)
        return utcNoon(year: local.year!, month: local.month!, day: local.day!)
    }

    // Capture the user's local calendar day once, then store it as UTC noon.
    // This keeps calculations consistent across time zones and daylight saving changes.
    static func localEvaluationDay(for date: Date = Date(), calendar: Calendar = .current) -> Date {
        utcNoon(for: date, in: calendar)
    }

    //convert a stored date for disp
    //it reverses the normalisation for display purposes
    static func displayDate(fromUTCNoon date: Date, in calendar: Calendar = .current) -> Date {
        let components = gregorianUTC.dateComponents([.year, .month, .day], from: date)
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        var localComponents = DateComponents()
        localComponents.calendar = gregorian
        localComponents.timeZone = calendar.timeZone
        localComponents.year = components.year
        localComponents.month = components.month
        localComponents.day = components.day
        localComponents.hour = 12
        return gregorian.date(from: localComponents) ?? date
    }

    //Count how many monthly deposits occur before a deadline
    static func monthsWithDeposits(from evaluationDate: Date, through targetDate: Date) -> Int {
        let evaluation = civilComponents(evaluationDate)
        let target = civilComponents(targetDate)
        
        //calculate diff in calendar months (ignoring days)
        let rawMonths = ((target.year! - evaluation.year!) * 12) + (target.month! - evaluation.month!)
        guard rawMonths > 0 else { return 0 }
        
        //find corresponding deposit anniversary
        let anniversary = clampedAnniversary(from: evaluationDate, addingMonths: rawMonths)
        
        //chekc if anniversary falls on or before deadline
        return anniversary <= targetDate ? rawMonths : max(rawMonths - 1, 0)
    }

    //Handle months with different numbers of days
    static func clampedAnniversary(from date: Date, addingMonths months: Int) -> Date {
        // Month-end dates stay month-end where possible, e.g. Jan 31 -> Feb 28/29.
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
