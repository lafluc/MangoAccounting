// FiscalCalendar.swift

import Foundation

/// The calendar every fiscal-year decision goes through.
///
/// `Calendar.current` resolves a stored `Date` in the device's *current* time
/// zone. A 1 January Zurich entry is stored as 31 December 23:00 UTC, so the same
/// database read on a machine set to a western time zone reported it a year
/// earlier — silently moving income and expenses across tax years on a report
/// headed "per 31.12.".
///
/// Pinning the calendar makes the fiscal year a property of the data rather than
/// of the machine reading it, and it does so for records already on disk.
enum FiscalCalendar {

    /// The app files Swiss accounts against the Swiss calendar year.
    static let timeZone = TimeZone(identifier: "Europe/Zurich") ?? TimeZone(secondsFromGMT: 0)!

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    static func year(of date: Date) -> Int {
        calendar.component(.year, from: date)
    }

    /// Half-open bounds for a fiscal year: `start <= date < end`.
    static func yearBounds(_ year: Int) -> (start: Date, end: Date) {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        let start = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return (start, end)
    }

    /// Renders a year without grouping separators. `NumberFormatter` was used for
    /// this and produced "2,025" in some locales.
    static func yearText(_ year: Int) -> String {
        String(year)
    }
}
