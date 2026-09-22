import XCTest
@testable import TradeJournal

@MainActor
final class CalendarViewModelTests: XCTestCase {

    private func makeCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2 // Maandag, zoals in Nederland gebruikelijk.
        return cal
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Weken

    func test_weeks_march2026_startsOnMondayAndCoversAllDays() {
        let calendar = makeCalendar()
        // Maart 2026 begint op zondag 1 maart en heeft 31 dagen.
        let reference = makeDate(2026, 3, 15, calendar: calendar)
        let viewModel = CalendarViewModel(calendar: calendar, referenceDate: reference)

        let weeks = viewModel.weeks
        XCTAssertFalse(weeks.isEmpty)
        for week in weeks { XCTAssertEqual(week.count, 7) }

        // 1 maart 2026 is een zondag → bij maandag-start staat hij aan het eind van week 1.
        XCTAssertNil(weeks[0][0], "Eerste weekdag (maandag) valt vóór 1 maart")
        XCTAssertEqual(weeks[0][6], makeDate(2026, 3, 1, calendar: calendar))

        let allDays = weeks.flatMap { $0 }.compactMap { $0 }
        XCTAssertEqual(allDays.count, 31)
        XCTAssertEqual(allDays.first, makeDate(2026, 3, 1, calendar: calendar))
        XCTAssertEqual(allDays.last, makeDate(2026, 3, 31, calendar: calendar))
    }

    // MARK: - Navigatie

    func test_nextAndPreviousMonth_moveDisplayedMonth() {
        let calendar = makeCalendar()
        let viewModel = CalendarViewModel(calendar: calendar, referenceDate: makeDate(2026, 3, 15, calendar: calendar))

        viewModel.nextMonth()
        var comps = calendar.dateComponents([.year, .month], from: viewModel.displayedMonth)
        XCTAssertEqual(comps.month, 4)

        viewModel.previousMonth()
        viewModel.previousMonth()
        comps = calendar.dateComponents([.year, .month], from: viewModel.displayedMonth)
        XCTAssertEqual(comps.month, 2)
    }

    func test_goToToday_resetsMonthAndYearAndClosesYearOverview() {
        let calendar = makeCalendar()
        let viewModel = CalendarViewModel(calendar: calendar, referenceDate: makeDate(2026, 3, 15, calendar: calendar))
        viewModel.showYearOverview = true
        viewModel.nextMonth()
        viewModel.nextYear()

        let now = makeDate(2026, 3, 15, calendar: calendar)
        viewModel.goToToday(now: now)

        XCTAssertFalse(viewModel.showYearOverview)
        XCTAssertEqual(viewModel.displayedYear, 2026)
        let comps = calendar.dateComponents([.year, .month], from: viewModel.displayedMonth)
        XCTAssertEqual(comps.month, 3)
    }

    func test_selectMonth_updatesDisplayedMonthAndClosesYearOverview() {
        let calendar = makeCalendar()
        let viewModel = CalendarViewModel(calendar: calendar, referenceDate: makeDate(2026, 1, 1, calendar: calendar))
        viewModel.showYearOverview = true

        viewModel.selectMonth(7, in: 2025)

        XCTAssertFalse(viewModel.showYearOverview)
        let comps = calendar.dateComponents([.year, .month], from: viewModel.displayedMonth)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 7)
    }

    // MARK: - Weektotalen

    func test_weekTotal_sumsKnownDaysAndIgnoresUnknownOnes() {
        let calendar = makeCalendar()
        let viewModel = CalendarViewModel(calendar: calendar, referenceDate: makeDate(2026, 3, 15, calendar: calendar))

        let day1 = makeDate(2026, 3, 2, calendar: calendar)
        let day2 = makeDate(2026, 3, 3, calendar: calendar)
        let aggregates: [Date: DayAggregate] = [
            day1: DayAggregate(date: day1, netPnL: 100, grossPnL: 100, tradeCount: 1, winCount: 1, lossCount: 0, breakevenCount: 0, openCount: 0, winRate: 1),
            day2: DayAggregate(date: day2, netPnL: -40, grossPnL: -40, tradeCount: 1, winCount: 0, lossCount: 1, breakevenCount: 0, openCount: 0, winRate: 0)
        ]

        // Week 1 (index 1) is maandag 2 t/m zondag 8 maart.
        let week = viewModel.weeks[1]
        let total = viewModel.weekTotal(for: week, dayAggregates: aggregates)
        XCTAssertEqual(total, 60, accuracy: 0.01)
    }
}
