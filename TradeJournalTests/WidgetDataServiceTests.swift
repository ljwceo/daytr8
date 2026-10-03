import XCTest
import SwiftData
@testable import TradeJournal

/// Rekenwerk achter de widgets: filters per widget, vergelijking met de
/// vorige periode, jaar-heatmap, R-histogram en top/flop.
@MainActor
final class WidgetDataServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let service = WidgetDataService()
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Long-trade op NQ (1 punt = $20 bij tick 0.25 / $5) met optionele stop voor R.
    @discardableResult
    private func trade(_ symbol: String = "NQ", on day: Date, points: Double, stopPoints: Double? = 10, account: Account? = nil) -> Trade {
        let trade = Trade(
            symbol: symbol, direction: .long, entryDate: day, exitDate: day.addingTimeInterval(600),
            entryPrice: 18_000, exitPrice: 18_000 + points, quantity: 1,
            stopLoss: stopPoints.map { 18_000 - $0 }, tickSize: 0.25, tickValue: 5, account: account
        )
        context.insert(trade)
        return trade
    }

    // MARK: - Filters

    func test_effectiveFilter_widgetOverridesPeriodAndAccounts() {
        let accountID = UUID()
        let base = DashboardFilterState(period: "thisMonth", symbolFilter: "NQ")
        let followed = service.effectiveFilter(base: base, settings: WidgetSettings())
        XCTAssertEqual(followed, base)

        let own = service.effectiveFilter(base: base, settings: WidgetSettings(period: .year, accountIDs: [accountID]))
        XCTAssertEqual(own.period, "thisYear")
        XCTAssertEqual(own.selectedAccountIDs, [accountID])
        XCTAssertEqual(own.symbolFilter, "NQ", "overige dashboardfilters blijven gelden")

        XCTAssertEqual(service.effectiveFilter(base: base, settings: WidgetSettings(), includePeriod: false).period, "all")
    }

    func test_trades_filteredByWidgetAccount() {
        let a = Account(name: "A", type: .live, startingBalance: 0)
        let b = Account(name: "B", type: .live, startingBalance: 0)
        context.insert(a)
        context.insert(b)
        let now = date(2026, 5, 20)
        let tradeA = trade(on: now, points: 5, account: a)
        trade(on: now, points: 5, account: b)
        let state = service.effectiveFilter(base: DashboardFilterState(), settings: WidgetSettings(accountIDs: [a.id]))
        XCTAssertEqual(service.trades(context.fetchAll(), matching: state, now: now, calendar: calendar).map(\.id), [tradeA.id])
    }

    // MARK: - Vorige periode

    func test_previousFilter_month_isPreviousCalendarMonth() throws {
        let now = date(2026, 5, 20)
        let state = DashboardFilterState(period: "thisMonth")
        let previous = try XCTUnwrap(service.previousFilter(of: state, now: now, calendar: calendar))
        XCTAssertEqual(previous.period, "custom")
        XCTAssertEqual(previous.customStart, date(2026, 4, 1, 0))
        XCTAssertLessThan(try XCTUnwrap(previous.customEnd), date(2026, 5, 1, 0))
        XCTAssertGreaterThan(try XCTUnwrap(previous.customEnd), date(2026, 4, 30, 23))
        XCTAssertNil(service.previousFilter(of: DashboardFilterState(period: "all"), now: now, calendar: calendar))
    }

    func test_comparison_netPnL_againstPreviousMonth() {
        let now = date(2026, 5, 20)
        trade(on: date(2026, 5, 4), points: 10)   // +200
        trade(on: date(2026, 5, 5), points: -5)   // -100
        trade(on: date(2026, 4, 10), points: 2)   // +40 (vorige maand)
        trade(on: date(2026, 3, 10), points: 50)  // telt niet mee
        let result = service.comparison(of: .netPnL, trades: context.fetchAll(), state: DashboardFilterState(period: "thisMonth"), now: now, calendar: calendar)
        XCTAssertEqual(result.current ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(result.previous ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(result.change ?? 0, 60, accuracy: 0.001)
    }

    func test_comparison_customPeriod_usesEqualLengthBefore() {
        let start = date(2026, 5, 11, 0)
        let end = date(2026, 5, 17, 23)
        trade(on: date(2026, 5, 12), points: 1)     // +20 in periode
        trade(on: date(2026, 5, 6), points: 3)      // +60 in de week ervoor
        trade(on: date(2026, 4, 1), points: 100)    // ver ervoor
        let state = DashboardFilterState(period: "custom", customStart: start, customEnd: end)
        let result = service.comparison(of: .netPnL, trades: context.fetchAll(), state: state, now: date(2026, 6, 1), calendar: calendar)
        XCTAssertEqual(result.current ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(result.previous ?? 0, 60, accuracy: 0.001)
    }

    func test_comparison_withoutPreviousTrades_hasNoChange() {
        trade(on: date(2026, 5, 4), points: 10)
        let result = service.comparison(of: .winRate, trades: context.fetchAll(), state: DashboardFilterState(period: "thisMonth"), now: date(2026, 5, 20), calendar: calendar)
        XCTAssertEqual(result.current, 1)
        XCTAssertNil(result.change)
    }

    func test_metricValues_matchStatsService() {
        trade(on: date(2026, 5, 4), points: 10)
        trade(on: date(2026, 5, 5), points: -5)
        let stats = StatsService().statistics(for: context.fetchAll())
        XCTAssertEqual(service.value(of: .netPnL, in: stats), stats.netPnL)
        XCTAssertEqual(service.value(of: .profitFactor, in: stats), stats.profitFactor)
        XCTAssertEqual(service.value(of: .tradeCount, in: stats), 2)
        XCTAssertEqual(service.value(of: .streak, in: stats), -1, "verliesstreak is negatief")
        XCTAssertNil(service.value(of: .averageWinLoss, in: stats))
    }

    // MARK: - Heatmap

    func test_heatmap_valuesPerMetric_andAvailableYears() {
        trade(on: date(2026, 3, 2), points: 10)    // +200, 1R
        trade(on: date(2026, 3, 2), points: -10)   // -200, -1R
        trade(on: date(2026, 3, 3), points: 20)    // +400, 2R
        trade(on: date(2024, 7, 1), points: 5)
        let trades: [Trade] = context.fetchAll()
        let day1 = date(2026, 3, 2, 0)
        let day2 = date(2026, 3, 3, 0)

        let pnl = service.heatmap(for: trades, year: 2026, metric: .netPnL, calendar: calendar)
        XCTAssertEqual(pnl.values[day1] ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(pnl.values[day2] ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(pnl.summary ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(pnl.availableYears, [2024, 2026])
        XCTAssertEqual(pnl.normalizedValue(for: day2), 1)
        XCTAssertNil(pnl.normalizedValue(for: date(2026, 3, 4, 0)))

        let count = service.heatmap(for: trades, year: 2026, metric: .tradeCount, calendar: calendar)
        XCTAssertEqual(count.values[day1], 2)
        XCTAssertEqual(count.summary, 3)
        XCTAssertFalse(count.isDiverging)

        let winRate = service.heatmap(for: trades, year: 2026, metric: .winRate, calendar: calendar)
        XCTAssertEqual(winRate.values[day1], 0.5)
        XCTAssertEqual(winRate.normalizedValue(for: day1), 0)
        XCTAssertEqual(winRate.normalizedValue(for: day2), 1)

        let r = service.heatmap(for: trades, year: 2026, metric: .rMultiple, calendar: calendar)
        XCTAssertEqual(r.values[day1] ?? 9, 0, accuracy: 0.001)
        XCTAssertEqual(r.values[day2] ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(r.summary ?? 0, 2, accuracy: 0.001)

        let empty = service.heatmap(for: trades, year: 2025, metric: .netPnL, calendar: calendar)
        XCTAssertTrue(empty.values.isEmpty)
        XCTAssertNil(empty.summary)
    }

    func test_heatmap_isFastWithManyYears() {
        // ~5 jaar, 4 trades per dag op werkdagen.
        var day = date(2021, 1, 4)
        var trades: [Trade] = []
        while day < date(2026, 1, 1) {
            if calendar.component(.weekday, from: day) % 7 > 1 {
                for index in 0..<4 { trades.append(trade(on: day.addingTimeInterval(Double(index) * 900), points: Double(index) - 1.5)) }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        measure {
            _ = service.heatmap(for: trades, year: 2025, metric: .netPnL, calendar: calendar)
        }
    }

    func test_yearHeatmapGrid_positionsAndTapLookup() throws {
        // 2026 begint op donderdag; met maandag als eerste dag = 3 lege rijen.
        let grid = try XCTUnwrap(YearHeatmapGrid(year: 2026, calendar: calendar))
        XCTAssertEqual(grid.days.count, 365)
        XCTAssertEqual(grid.leadingEmptyRows, 3)
        XCTAssertEqual(grid.columnCount, 53)
        XCTAssertEqual(grid.position(ofDayAt: 0).column, 0)
        XCTAssertEqual(grid.position(ofDayAt: 0).row, 3)
        XCTAssertEqual(grid.day(column: 0, row: 3), date(2026, 1, 1, 0))
        XCTAssertNil(grid.day(column: 0, row: 2), "vóór 1 januari")
        XCTAssertNil(grid.day(column: 60, row: 0))
        XCTAssertEqual(grid.monthMarkers.count, 12)
        XCTAssertEqual(grid.monthMarkers.first, YearHeatmapGrid.MonthMarker(month: 1, column: 0))
        for (index, day) in grid.days.enumerated() {
            let position = grid.position(ofDayAt: index)
            XCTAssertEqual(grid.day(column: position.column, row: position.row), day)
        }
        let leap = try XCTUnwrap(YearHeatmapGrid(year: 2024, calendar: calendar))
        XCTAssertEqual(leap.days.count, 366)
    }

    // MARK: - R-histogram

    func test_rHistogram_bucketsAndOverflow() {
        trade(on: date(2026, 5, 4), points: -10)              // -1R
        trade(on: date(2026, 5, 4), points: 15)               // 1.5R
        trade(on: date(2026, 5, 4), points: 60)               // 6R → overloop
        trade(on: date(2026, 5, 4), points: -40)              // -4R → overloop
        trade(on: date(2026, 5, 4), points: 5, stopPoints: nil) // geen R
        let buckets = service.rHistogram(for: context.fetchAll(), bucketWidth: 1, lowerLimit: -3, upperLimit: 5)
        XCTAssertEqual(buckets.first?.label, "<-3R")
        XCTAssertEqual(buckets.first?.count, 1)
        XCTAssertEqual(buckets.last?.label, "≥5R")
        XCTAssertEqual(buckets.last?.count, 1)
        XCTAssertEqual(buckets.count, 10)
        XCTAssertEqual(buckets.first { $0.lowerBound == -1 }?.count, 1)
        XCTAssertTrue(buckets.first { $0.lowerBound == -1 }?.isLoss ?? false)
        XCTAssertEqual(buckets.first { $0.lowerBound == 1 }?.count, 1)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.count }, 4)
        XCTAssertTrue(service.rHistogram(for: []).isEmpty)
    }

    // MARK: - Top/flop

    func test_topFlop_bySymbol_noOverlap() {
        let day = date(2026, 5, 4)
        trade("NQ", on: day, points: 10)
        trade("ES", on: day, points: -3)
        trade("CL", on: day, points: 1)
        let lists = service.topFlop(for: context.fetchAll(), dimension: .symbol, count: 3)
        XCTAssertEqual(lists.top.map(\.label), ["NQ", "CL"])
        XCTAssertEqual(lists.flop.map(\.label), ["ES"])

        let one = service.topFlop(for: context.fetchAll(), dimension: .symbol, count: 1)
        XCTAssertEqual(one.top.map(\.label), ["NQ"])
        XCTAssertEqual(one.flop.map(\.label), ["ES"])
    }

    // MARK: - Cache

    func test_cache_reusesUntilVersionChanges() {
        let cache = WidgetComputationCache()
        var calls = 0
        let first = cache.value("a", version: "1") { calls += 1; return 1 }
        let second = cache.value("a", version: "1") { calls += 1; return 2 }
        let third = cache.value("a", version: "2") { calls += 1; return 3 }
        XCTAssertEqual([first, second, third], [1, 1, 3])
        XCTAssertEqual(calls, 2)
    }

    /// Regressie: een optioneel resultaat (zoals het heatmap-raster) werd
    /// nooit berekend, waardoor de heatmap leeg bleef.
    func test_cache_computesOptionalValues() {
        let cache = WidgetComputationCache()
        var calls = 0
        let first: Int? = cache.value("grid", version: "1") { calls += 1; return 7 }
        let second: Int? = cache.value("grid", version: "1") { calls += 1; return 8 }
        XCTAssertEqual(first, 7)
        XCTAssertEqual(second, 7)
        XCTAssertEqual(calls, 1)
        let none: Int? = cache.value("leeg", version: "1") { calls += 1; return nil }
        XCTAssertNil(none)
        let grid: YearHeatmapGrid? = cache.value("raster", version: "1") { YearHeatmapGrid(year: 2026, calendar: calendar) }
        XCTAssertEqual(grid?.days.count, 365)
    }

    // MARK: - Grafiekpunten

    func test_chartSampling_dedupesDatesAndKeepsExtremes() {
        let start = date(2024, 1, 1)
        var points: [DateValuePoint] = []
        for index in 0..<2_000 {
            let value = index == 1_234 ? 99_999 : (index == 777 ? -88_888 : Double(index))
            points.append(DateValuePoint(date: start.addingTimeInterval(Double(index) * 3_600), value: value))
        }
        // Twee trades op hetzelfde tijdstip: alleen de laatste telt.
        points.append(DateValuePoint(date: start, value: 5))

        let sampled = ChartSampling.downsample(points, maxPoints: 300)
        XCTAssertLessThanOrEqual(sampled.count, 302)
        XCTAssertTrue(sampled.contains { $0.value == 99_999 }, "piek blijft")
        XCTAssertTrue(sampled.contains { $0.value == -88_888 }, "dal blijft")
        XCTAssertEqual(sampled.last?.value, 1_999)
        XCTAssertEqual(sampled.first?.date, start)
        for (a, b) in zip(sampled, sampled.dropFirst()) {
            XCTAssertLessThan(a.date, b.date, "strikt oplopend")
        }

        let few = [DateValuePoint(date: start, value: 1), DateValuePoint(date: start, value: 2), DateValuePoint(date: start.addingTimeInterval(60), value: 3)]
        XCTAssertEqual(ChartSampling.downsample(few).map(\.value), [2, 3])
    }
}

private extension ModelContext {
    func fetchAll() -> [Trade] {
        (try? fetch(FetchDescriptor<Trade>())) ?? []
    }
}
