import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class StatsServiceTests: XCTestCase {

    // MARK: - Shared in-memory container

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var stats: StatsService { StatsService() }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeTrade(
        direction: TradeDirection = .long,
        entry: Double,
        exit: Double?,
        quantity: Double = 1,
        tickSize: Double = 0.25,
        tickValue: Double = 5.0,
        stopLoss: Double? = nil,
        plannedRisk: Double? = nil,
        commission: Double = 0,
        fees: Double = 0,
        entryDate: Date = Date(timeIntervalSince1970: 1_720_000_000),
        exitDate: Date? = Date(timeIntervalSince1970: 1_720_003_600),
        insert: Bool = true
    ) -> Trade {
        let trade = Trade(
            symbol: "NQ",
            direction: direction,
            entryDate: entryDate,
            exitDate: exit == nil ? nil : exitDate,
            entryPrice: entry,
            exitPrice: exit,
            quantity: quantity,
            stopLoss: stopLoss,
            plannedRisk: plannedRisk,
            commission: commission,
            fees: fees,
            tickSize: tickSize,
            tickValue: tickValue
        )
        if insert { context.insert(trade) }
        return trade
    }

    // MARK: - P&L per trade

    func test_longWin_grossAndNetPnL() {
        let t = makeTrade(entry: 18_000, exit: 18_010, quantity: 2, commission: 4, fees: 1)
        let m = stats.metrics(for: t)
        // 10 punten * (5 / 0.25) = 200 per contract * 2 = 400
        XCTAssertEqual(m.grossPnL, 400, accuracy: 1e-6)
        XCTAssertEqual(m.netPnL, 400 - 4 - 1, accuracy: 1e-6)
        XCTAssertEqual(m.outcome, .win)
        XCTAssertEqual(m.signedTicks, 40, accuracy: 1e-6)
    }

    func test_shortWin_countsPriceDropAsProfit() {
        let t = makeTrade(direction: .short, entry: 18_000, exit: 17_990, quantity: 1)
        let m = stats.metrics(for: t)
        XCTAssertEqual(m.grossPnL, 200, accuracy: 1e-6)
        XCTAssertEqual(m.outcome, .win)
        XCTAssertEqual(m.signedTicks, 40, accuracy: 1e-6)
    }

    func test_shortLoss_countsPriceRiseAsLoss() {
        let t = makeTrade(direction: .short, entry: 18_000, exit: 18_020)
        let m = stats.metrics(for: t)
        XCTAssertEqual(m.grossPnL, -400, accuracy: 1e-6)
        XCTAssertEqual(m.outcome, .loss)
    }

    func test_openTrade_hasZeroPnLAndOpenOutcome() {
        let t = makeTrade(entry: 18_000, exit: nil, exitDate: nil)
        let m = stats.metrics(for: t)
        XCTAssertEqual(m.grossPnL, 0, accuracy: 1e-9)
        XCTAssertEqual(m.netPnL, 0, accuracy: 1e-9)
        XCTAssertEqual(m.outcome, .open)
        XCTAssertNil(m.rMultiple)
    }

    func test_breakeven_withinTolerance() {
        let t = makeTrade(entry: 18_000, exit: 18_000, commission: 0)
        let m = stats.metrics(for: t)
        XCTAssertEqual(m.netPnL, 0, accuracy: 1e-9)
        XCTAssertEqual(m.outcome, .breakeven)
    }

    // MARK: - R-multiple

    func test_rMultiple_fromPlannedRisk() {
        let t = makeTrade(entry: 18_000, exit: 18_020, quantity: 1, plannedRisk: 100, commission: 5)
        let m = stats.metrics(for: t)
        // netPnL = 400 - 5 = 395; R = 395 / 100 = 3.95
        XCTAssertEqual(m.rMultiple ?? .nan, 3.95, accuracy: 1e-9)
    }

    func test_rMultiple_derivedFromStopDistance() {
        // Stop 20 punten weg → 20 * (5/0.25) = 400 risk per contract, ×1 contract = 400.
        let t = makeTrade(entry: 18_000, exit: 18_040, quantity: 1, stopLoss: 17_980)
        let m = stats.metrics(for: t)
        // grossPnL = 40 punten * 20 = 800; risk = 400; R = 2
        XCTAssertEqual(m.riskAmount ?? .nan, 400, accuracy: 1e-6)
        XCTAssertEqual(m.rMultiple ?? .nan, 2.0, accuracy: 1e-9)
    }

    func test_rMultiple_nilWithoutRiskInfo() {
        let t = makeTrade(entry: 18_000, exit: 18_040)
        let m = stats.metrics(for: t)
        XCTAssertNil(m.rMultiple)
        XCTAssertNil(m.riskAmount)
    }

    // MARK: - Partial exits

    func test_partialExits_realizedPnLIsSumOfMatchedLots() {
        let t = makeTrade(entry: 18_000, exit: nil, quantity: 2, exitDate: nil)
        let e1 = TradeExecution(date: Date(timeIntervalSince1970: 1_720_000_000), price: 18_000, signedQuantity: 2)
        let e2 = TradeExecution(date: Date(timeIntervalSince1970: 1_720_003_000), price: 18_010, signedQuantity: -1, commission: 2)
        let e3 = TradeExecution(date: Date(timeIntervalSince1970: 1_720_005_000), price: 18_020, signedQuantity: -1, commission: 2, fees: 1)
        context.insert(e1); context.insert(e2); context.insert(e3)
        t.executions = [e1, e2, e3]

        let m = stats.metrics(for: t)
        XCTAssertEqual(m.grossPnL, 600, accuracy: 1e-6)
        XCTAssertEqual(m.netPnL, 600 - 4 - 1, accuracy: 1e-6)
        XCTAssertEqual(m.outcome, .win)
    }

    func test_partialExit_leavingPositionOpen() {
        let t = makeTrade(entry: 18_000, exit: nil, quantity: 2, exitDate: nil)
        let e1 = TradeExecution(date: Date(timeIntervalSince1970: 1), price: 18_000, signedQuantity: 2)
        let e2 = TradeExecution(date: Date(timeIntervalSince1970: 100), price: 18_010, signedQuantity: -1)
        context.insert(e1); context.insert(e2)
        t.executions = [e1, e2]

        let m = stats.metrics(for: t)
        XCTAssertEqual(m.outcome, .open)
        XCTAssertEqual(m.grossPnL, 200, accuracy: 1e-6, "Realised P&L van gesloten deel moet meetellen")
    }

    // MARK: - Aggregatie

    func test_statistics_forSimpleWinLossSequence() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let pnls: [Double] = [100, 100, 100, -50, -50]
        let trades: [Trade] = pnls.enumerated().map { idx, pnl in
            makeTrade(
                entry: 100,
                exit: 100 + pnl / (5 / 0.25),
                quantity: 1,
                entryDate: base.addingTimeInterval(TimeInterval(idx) * 3600),
                exitDate: base.addingTimeInterval(TimeInterval(idx) * 3600 + 60)
            )
        }
        let s = stats.statistics(for: trades)
        XCTAssertEqual(s.tradeCount, 5)
        XCTAssertEqual(s.winCount, 3)
        XCTAssertEqual(s.lossCount, 2)
        XCTAssertEqual(s.netPnL, 200, accuracy: 1e-6)
        XCTAssertEqual(s.winRate, 0.6, accuracy: 1e-6)
        XCTAssertEqual(s.averageWin, 100, accuracy: 1e-6)
        XCTAssertEqual(s.averageLoss, -50, accuracy: 1e-6)
        XCTAssertEqual(s.profitFactor ?? .nan, 3.0, accuracy: 1e-6)
        XCTAssertEqual(s.expectancy, 40, accuracy: 1e-6)
        XCTAssertEqual(s.largestWin, 100, accuracy: 1e-6)
        XCTAssertEqual(s.largestLoss, -50, accuracy: 1e-6)
    }

    func test_statistics_streaksAndDrawdown() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let pnls: [Double] = [100, 100, -100, -100, -100, 100, 200]
        let trades: [Trade] = pnls.enumerated().map { idx, pnl in
            makeTrade(
                entry: 100,
                exit: 100 + pnl / (5 / 0.25),
                quantity: 1,
                entryDate: base.addingTimeInterval(TimeInterval(idx) * 3600),
                exitDate: base.addingTimeInterval(TimeInterval(idx) * 3600 + 60)
            )
        }
        let s = stats.statistics(for: trades)

        // Cum: 100, 200, 100, 0, -100, 0, 200 → peak 200, low -100 → dd 300
        XCTAssertEqual(s.maxDrawdown, 300, accuracy: 1e-6)
        XCTAssertEqual(s.longestLossStreak, 3)
        XCTAssertEqual(s.longestWinStreak, 2)
        XCTAssertEqual(s.currentStreak, 2)
        XCTAssertEqual(s.currentStreakIsWinning, true)
    }

    func test_statistics_emptyReturnsZero() {
        XCTAssertEqual(stats.statistics(for: []), .empty)
    }

    func test_statistics_ignoresOpenTradesForPnLButCountsThemInOpenCount() {
        let closed = makeTrade(entry: 100, exit: 100 + 100 / (5 / 0.25))
        let open = makeTrade(
            entry: 100, exit: nil,
            entryDate: Date(timeIntervalSince1970: 1_720_010_000),
            exitDate: nil
        )

        let s = stats.statistics(for: [closed, open])
        XCTAssertEqual(s.tradeCount, 2)
        XCTAssertEqual(s.openCount, 1)
        XCTAssertEqual(s.winCount, 1)
        XCTAssertEqual(s.netPnL, 100, accuracy: 1e-6)
    }

    func test_averageRMultiple() {
        // Twee trades met R = 2 en R = -1 → gemiddeld 0.5
        let a = makeTrade(entry: 18_000, exit: 18_040, stopLoss: 17_980)   // R = 2
        let b = makeTrade(
            entry: 18_000, exit: 17_980, stopLoss: 17_980,
            entryDate: Date(timeIntervalSince1970: 1_720_010_000),
            exitDate: Date(timeIntervalSince1970: 1_720_013_600)
        )   // R = -1
        let s = stats.statistics(for: [a, b])
        XCTAssertEqual(s.averageRMultiple ?? .nan, 0.5, accuracy: 1e-6)
    }

    func test_equityCurve_isCumulative() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let a = makeTrade(
            entry: 100, exit: 100 + 50 / (5/0.25),
            entryDate: base,
            exitDate: base.addingTimeInterval(60)
        )
        let b = makeTrade(
            entry: 100, exit: 100 - 25 / (5/0.25),
            entryDate: base.addingTimeInterval(120),
            exitDate: base.addingTimeInterval(180)
        )
        let curve = stats.equityCurve(for: [a, b], startingBalance: 1_000)
        XCTAssertEqual(curve.count, 2)
        XCTAssertEqual(curve[0].equity, 1_050, accuracy: 1e-6)
        XCTAssertEqual(curve[1].equity, 1_025, accuracy: 1e-6)
    }

    func test_recomputeSession_setsBasedOnEntryDate() {
        let ny = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        let entry = cal.date(from: DateComponents(year: 2024, month: 7, day: 10, hour: 9, minute: 30))!
        let t = makeTrade(
            entry: 100, exit: 100,
            entryDate: entry, exitDate: entry.addingTimeInterval(600)
        )
        stats.recomputeSession(for: t)
        XCTAssertEqual(t.session, .nyAM)
    }
}
