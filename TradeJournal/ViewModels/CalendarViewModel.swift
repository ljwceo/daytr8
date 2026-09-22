import Foundation

/// UI-state en zuivere rasterlogica voor `CalendarView`: welke maand/jaar
/// getoond wordt, welke dag geselecteerd is, en de weekindeling van de
/// getoonde maand. Houdt zelf geen trades of aggregaten vast — de view
/// berekent die via `CalendarAggregationService` en geeft ze door aan de
/// subviews, zodat deze klasse puur en unit-testbaar blijft.
@Observable
public final class CalendarViewModel {

    public var displayedMonth: Date
    public var displayedYear: Int
    public var selectedDate: Date?
    public var showYearOverview: Bool = false

    public let calendar: Calendar

    public init(calendar: Calendar = .current, referenceDate: Date = Date()) {
        self.calendar = calendar
        self.displayedMonth = Self.startOfMonth(for: referenceDate, calendar: calendar)
        self.displayedYear = calendar.component(.year, from: referenceDate)
    }

    // MARK: - Navigatie

    public func goToToday(now: Date = Date()) {
        displayedMonth = Self.startOfMonth(for: now, calendar: calendar)
        displayedYear = calendar.component(.year, from: now)
        showYearOverview = false
    }

    public func nextMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    public func previousMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    public func nextYear() {
        displayedYear += 1
    }

    public func previousYear() {
        displayedYear -= 1
    }

    public func selectMonth(_ month: Int, in year: Int) {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        if let date = calendar.date(from: comps) {
            displayedMonth = Self.startOfMonth(for: date, calendar: calendar)
        }
        showYearOverview = false
    }

    // MARK: - Weergave

    public var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    /// Weekdag-afkortingen in de volgorde van `calendar.firstWeekday`.
    public var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        guard offset > 0, offset < symbols.count else { return symbols }
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// Weken (van 7 dagen) voor `displayedMonth`. `nil` staat voor een dag
    /// buiten de maand (opvulling aan begin/eind van de eerste/laatste week).
    public var weeks: [[Date?]] {
        Self.weeks(forMonth: displayedMonth, calendar: calendar)
    }

    /// Weken (van 7 dagen) voor een willekeurige maand, herbruikt door zowel
    /// de maandweergave als de mini-maanden in het jaaroverzicht.
    public static func weeks(forMonth month: Date, calendar: Calendar) -> [[Date?]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 0

        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for dayOffset in 0..<daysInMonth {
            days.append(calendar.date(byAdding: .day, value: dayOffset, to: firstOfMonth))
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    /// Som van `netPnL` van alle bekende dagen in `week`.
    public func weekTotal(for week: [Date?], dayAggregates: [Date: DayAggregate]) -> Double {
        week.compactMap { $0 }.reduce(0) { partial, date in
            partial + (dayAggregates[calendar.startOfDay(for: date)]?.netPnL ?? 0)
        }
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }
}
