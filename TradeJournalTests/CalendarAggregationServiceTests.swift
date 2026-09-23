import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class CalendarAggregationServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let service = CalendarAggregationService()
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    @discardableResult
    private func makeTrade(entryDate: Date, exitDate: Date?, entry: Double, exit: Double?) -> Trade {
        let trade = Trade(
            symbol: "NQ",
            direction: .long,
            entryDate: entryDate,
            exitDate: exitDate,
            entryPrice: entry,
            exitPrice: exit,
            quantity: 1,
            tickSize: 0.25,
            tickValue: 5.0
        )
        context.insert(trade)
        return trade
    }

    // MARK: - dayAggregates

    func test_dayAggregates_groupsClosedTradeOnExitDay() throws {
        var comps = DateComponents(year: 2026, month: 3, day: 10, hour: 9)
        comps.timeZone = calendar.timeZone
        let entry = calendar.date(from: comps)!
        let exitComps = DateComponents(timeZone: calendar.timeZone, year: 2026, month: 3, day: 11, hour: 2)
        let exit = calendar.date(from: exitComps)!

        let trade = makeTrade(entryDate: entry, exitDate: exit, entry: 18_000, exit: 18_010)

        let aggregates = service.dayAggregates(for: [trade], calendar: calendar)

        XCTAssertNil(aggregates[calendar.startOfDay(for: entry)], "Trade sluit op een andere dag dan hij opende")
        let exitDay = aggregates[calendar.startOfDay(for: exit)]
        XCTAssertEqual(exitDay?.tradeCount, 1)
        XCTAssertEqual(exitDay?.netPnL ?? 0, 200, accuracy: 0.01)
        XCTAssertEqual(exitDay?.winCount, 1)
    }

    func test_dayAggregates_groupsOpenTradeOnEntryDay() throws {
        let entry = Date(timeIntervalSince1970: 1_720_000_000)
        let trade = makeTrade(entryDate: entry, exitDate: nil, entry: 18_000, exit: nil)

        let aggregates = service.dayAggregates(for: [trade], calendar: calendar)

        let day = aggregates[calendar.startOfDay(for: entry)]
        XCTAssertEqual(day?.tradeCount, 1)
        XCTAssertEqual(day?.openCount, 1)
        XCTAssertEqual(day?.netPnL, 0)
    }

    func test_dayAggregates_combinesMultipleTradesOnSameDay() throws {
        let day1 = Date(timeIntervalSince1970: 1_720_000_000)
        let day1Later = day1.addingTimeInterval(3600)

        let win = makeTrade(entryDate: day1, exitDate: day1Later, entry: 18_000, exit: 18_010)
        let loss = makeTrade(entryDate: day1Later, exitDate: day1Later.addingTimeInterval(600), entry: 18_010, exit: 18_005)

        let aggregates = service.dayAggregates(for: [win, loss], calendar: calendar)
        let day = aggregates[calendar.startOfDay(for: day1)]

        XCTAssertEqual(day?.tradeCount, 2)
        XCTAssertEqual(day?.winCount, 1)
        XCTAssertEqual(day?.lossCount, 1)
        // (18010-18000)/0.25*5 - (18010-18005)/0.25*5 = 200 - 100 = 100
        XCTAssertEqual(day?.netPnL ?? 0, 100, accuracy: 0.01)
    }

    // MARK: - monthAggregates

    func test_monthAggregates_rollsUpDaysIntoMonths() throws {
        let day1 = Date(timeIntervalSince1970: 1_720_000_000)
        let sameMonthLater = calendar.date(byAdding: .day, value: 3, to: day1)!

        let t1 = makeTrade(entryDate: day1, exitDate: day1, entry: 18_000, exit: 18_010)
        let t2 = makeTrade(entryDate: sameMonthLater, exitDate: sameMonthLater, entry: 18_000, exit: 17_990)

        let dayAggregates = service.dayAggregates(for: [t1, t2], calendar: calendar)
        let monthAggregates = service.monthAggregates(fromDayAggregates: dayAggregates, calendar: calendar)

        let monthComps = calendar.dateComponents([.year, .month], from: day1)
        let monthKey = calendar.date(from: monthComps)!
        let month = monthAggregates[monthKey]

        XCTAssertEqual(month?.tradeCount, 2)
        // +200 - 200 = 0
        XCTAssertEqual(month?.netPnL ?? -1, 0, accuracy: 0.01)
    }
}
