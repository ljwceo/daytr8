import XCTest
@testable import TradeJournal

/// Tik op de jaar-heatmap → dichtstbijzijnde maand (`YearHeatmapGrid`) en de
/// route naar de maandweergave van de Kalender-tab.
final class HeatmapMonthNavigationTests: XCTestCase {

    /// Maandag als eerste dag van de week, UTC.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// 2024: schrikkeljaar, 1 januari is een maandag (geen lege rijen).
    /// Begin-kolommen: jan 0, feb 4, mrt 8, apr 13, ..., dec 47.
    private func grid2024() throws -> YearHeatmapGrid {
        try XCTUnwrap(YearHeatmapGrid(year: 2024, calendar: calendar))
    }

    /// 2023: geen schrikkeljaar, 1 januari is een zondag (6 lege rijen).
    /// Begin-kolommen: jan 0, feb 5, mrt 9, ..., dec 48.
    private func grid2023() throws -> YearHeatmapGrid {
        try XCTUnwrap(YearHeatmapGrid(year: 2023, calendar: calendar))
    }

    // MARK: - x-positie → maand

    func test_markers_matchExpectedColumns() throws {
        let leap = try grid2024()
        XCTAssertEqual(leap.monthMarkers.map(\.column).prefix(4), [0, 4, 8, 13])
        XCTAssertEqual(leap.monthMarkers.last, YearHeatmapGrid.MonthMarker(month: 12, column: 47))
        let normal = try grid2023()
        XCTAssertEqual(normal.monthMarkers.map(\.column).prefix(3), [0, 5, 9])
        XCTAssertEqual(normal.monthMarkers.last, YearHeatmapGrid.MonthMarker(month: 12, column: 48))
    }

    func test_tapInMiddleOfMonth() throws {
        let grid = try grid2024()
        XCTAssertEqual(grid.month(atColumn: 2), 1)
        XCTAssertEqual(grid.month(atColumn: 6.5), 2)
        XCTAssertEqual(grid.month(atColumn: 10.5), 3)
        XCTAssertEqual(grid.month(atColumn: 50), 12)
        // Elke maand is te bereiken: een halve kolom na zijn begin-kolom.
        for marker in grid.monthMarkers {
            XCTAssertEqual(grid.month(atColumn: Double(marker.column) + 0.5), marker.month)
        }
    }

    func test_tapOnBoundaryBetweenMonths() throws {
        let grid = try grid2024()
        // De kolom waarin maart begint hoort bij maart; net ervoor is februari.
        XCTAssertEqual(grid.month(atColumn: 8), 3)
        XCTAssertEqual(grid.month(atColumn: 7.99), 2)
        XCTAssertEqual(grid.month(atColumn: 4), 2)
        XCTAssertEqual(grid.month(atColumn: 3.99), 1)
    }

    func test_tapLeftOfJanuary_clampsToJanuary() throws {
        let grid = try grid2024()
        XCTAssertEqual(grid.month(atColumn: -0.5), 1)
        XCTAssertEqual(grid.month(atColumn: -100), 1)
        // Tik op de weekdaglabels (links van het raster).
        XCTAssertEqual(grid.month(atX: 5, leadingInset: 20, cellSize: 10), 1)
        XCTAssertEqual(grid.month(atColumn: -.infinity), 1)
    }

    func test_tapRightOfDecember_clampsToDecember() throws {
        let grid = try grid2024()
        XCTAssertEqual(grid.month(atColumn: Double(grid.columnCount)), 12)
        XCTAssertEqual(grid.month(atColumn: 1_000), 12)
        XCTAssertEqual(grid.month(atX: 2_000, leadingInset: 20, cellSize: 10), 12)
        XCTAssertEqual(grid.month(atColumn: .infinity), 12)
    }

    func test_pointsToColumns() throws {
        let grid = try grid2024()
        // 20 pt labels, 10 pt per kolom: maart begint op x = 20 + 8 × 10.
        XCTAssertEqual(grid.month(atX: 100, leadingInset: 20, cellSize: 10), 3)
        XCTAssertEqual(grid.month(atX: 99, leadingInset: 20, cellSize: 10), 2)
        // Ongeldige celgrootte: veilig januari.
        XCTAssertEqual(grid.month(atX: 100, leadingInset: 20, cellSize: 0), 1)
    }

    func test_leapYearAndNonLeapYear() throws {
        let leap = try grid2024()
        let normal = try grid2023()
        XCTAssertEqual(leap.days.count, 366)
        XCTAssertEqual(normal.days.count, 365)
        // Kolom 8 is in 2024 al maart, in 2023 nog februari.
        XCTAssertEqual(leap.month(atColumn: 8.5), 3)
        XCTAssertEqual(normal.month(atColumn: 8.5), 2)
        XCTAssertEqual(normal.month(atColumn: 9), 3)
        // Grenzen en randen werken in beide jaren.
        for grid in [leap, normal] {
            XCTAssertEqual(grid.month(atColumn: -1), 1)
            XCTAssertEqual(grid.month(atColumn: Double(grid.columnCount) + 1), 12)
            for marker in grid.monthMarkers {
                XCTAssertEqual(grid.month(atColumn: Double(marker.column)), marker.month)
            }
        }
    }

    // MARK: - Route naar de Kalender-tab

    func test_openCalendarMonth_selectsCalendarTabAndRequestsMonth() {
        let suiteName = "HeatmapMonthNavigationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let navigation = OnboardingViewModel(settings: OnboardingSettings(defaults: defaults))

        navigation.openCalendarMonth(3, year: 2024)
        XCTAssertEqual(navigation.selectedTab, .calendar)
        XCTAssertEqual(navigation.calendarMonthRequest?.month, 3)
        XCTAssertEqual(navigation.calendarMonthRequest?.year, 2024)

        // Eén keer af te nemen.
        let route = navigation.consumeCalendarMonthRequest()
        XCTAssertEqual(route?.month, 3)
        XCTAssertNil(navigation.calendarMonthRequest)
        XCTAssertNil(navigation.consumeCalendarMonthRequest())

        // Dezelfde maand opnieuw is een nieuw verzoek.
        navigation.openCalendarMonth(3, year: 2024)
        let again = navigation.consumeCalendarMonthRequest()
        XCTAssertNotNil(again)
        XCTAssertNotEqual(again?.id, route?.id)
    }

    func test_route_clampsMonth() {
        XCTAssertEqual(CalendarMonthRoute(year: 2024, month: 0).month, 1)
        XCTAssertEqual(CalendarMonthRoute(year: 2024, month: 13).month, 12)
    }

    func test_calendarViewModel_showRoute_opensMonthView() throws {
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3)))
        let viewModel = CalendarViewModel(calendar: calendar, referenceDate: reference)
        viewModel.showYearOverview = true
        viewModel.selectedDate = reference

        viewModel.show(CalendarMonthRoute(year: 2024, month: 2))

        XCTAssertEqual(viewModel.displayedMonth, calendar.date(from: DateComponents(year: 2024, month: 2, day: 1)))
        XCTAssertEqual(viewModel.displayedYear, 2024)
        XCTAssertFalse(viewModel.showYearOverview, "maandweergave, niet het jaaroverzicht")
        XCTAssertNil(viewModel.selectedDate, "open dagdetail sluit")
        // Februari 2024 (schrikkeljaar) heeft 29 dagen in het raster.
        XCTAssertEqual(viewModel.weeks.flatMap { $0 }.compactMap { $0 }.count, 29)
    }
}
