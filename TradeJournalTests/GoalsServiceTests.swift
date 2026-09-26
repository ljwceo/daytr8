import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class GoalsServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let service = GoalsService()
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func date(month: Int = 3, _ day: Int, _ hour: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// NQ: $20 per punt.
    @discardableResult
    private func makeTrade(_ account: Account, month: Int = 3, day: Int, hour: Int = 15, points: Double, isBacktest: Bool = false) -> Trade {
        let entry = date(month: month, day, hour)
        let trade = Trade(
            symbol: "NQ", direction: .long, entryDate: entry, exitDate: entry.addingTimeInterval(300),
            entryPrice: 18_000, exitPrice: 18_000 + points, quantity: 1,
            tickSize: 0.25, tickValue: 5, isBacktest: isBacktest, account: account
        )
        context.insert(trade)
        return trade
    }

    private func makeAccount(type: AccountType = .propFirm, target: Double? = nil, daily: Double? = nil, drawdown: Double? = nil) -> Account {
        let account = Account(name: "Topstep", type: type, startingBalance: 50_000, maxDrawdown: drawdown, dailyLossLimit: daily, monthlyProfitTarget: target)
        context.insert(account)
        return account
    }

    func test_limitStatus_levels() {
        XCTAssertEqual(service.limitStatus(used: 500, limit: 1_000).level, .ok)
        XCTAssertEqual(service.limitStatus(used: 800, limit: 1_000).level, .warning)
        XCTAssertEqual(service.limitStatus(used: 1_000, limit: 1_000).level, .breached)
        XCTAssertEqual(service.limitStatus(used: -300, limit: 1_000).used, 0)
        XCTAssertEqual(service.limitStatus(used: 1_500, limit: 1_000).fraction, 1)
        XCTAssertEqual(service.limitStatus(used: 250, limit: 1_000).remaining, 750)
    }

    func test_noGoals_returnsNil() {
        let account = makeAccount()
        XCTAssertNil(service.status(for: account, trades: [], now: date(10), calendar: calendar))
    }

    func test_monthlyTarget_countsOnlyCurrentMonth() {
        let account = makeAccount(target: 1_000)
        let trades = [
            makeTrade(account, month: 2, day: 27, points: 50),   // vorige maand: telt niet
            makeTrade(account, day: 3, points: 10),              // +200
            makeTrade(account, day: 5, points: 20)               // +400
        ]
        let status = service.status(for: account, trades: trades, now: date(10), calendar: calendar)
        XCTAssertEqual(status?.monthlyTarget?.current ?? 0, 600, accuracy: 0.001)
        XCTAssertEqual(status?.monthlyTarget?.fraction ?? 0, 0.6, accuracy: 0.001)
        XCTAssertEqual(status?.monthlyTarget?.isReached, false)
    }

    func test_dailyLoss_warningWhenClose() {
        let account = makeAccount(daily: 1_000)
        let trades = [
            makeTrade(account, day: 9, points: -100),            // gisteren: telt niet
            makeTrade(account, day: 10, hour: 14, points: -30),  // -600
            makeTrade(account, day: 10, hour: 15, points: -12)   // -240 → -840
        ]
        let status = service.status(for: account, trades: trades, now: date(10, 18), calendar: calendar)
        XCTAssertEqual(status?.dailyLoss?.used ?? 0, 840, accuracy: 0.001)
        XCTAssertEqual(status?.dailyLoss?.level, .warning)
        XCTAssertEqual(status?.level, .warning)
    }

    func test_dailyLoss_profitableDay_isOk() {
        let account = makeAccount(daily: 1_000)
        let status = service.status(for: account, trades: [makeTrade(account, day: 10, points: 10)], now: date(10, 18), calendar: calendar)
        XCTAssertEqual(status?.dailyLoss?.used, 0)
        XCTAssertEqual(status?.dailyLoss?.level, .ok)
    }

    func test_drawdown_isTrailingFromPeak() {
        let account = makeAccount(drawdown: 2_000)
        let trades = [
            makeTrade(account, day: 2, points: 50),   // +1000 → piek 51.000
            makeTrade(account, day: 3, points: -40),  // -800
            makeTrade(account, day: 4, points: -35)   // -700 → 49.500, drawdown 1.500
        ]
        let status = service.status(for: account, trades: trades, now: date(10), calendar: calendar)
        XCTAssertEqual(status?.drawdown?.used ?? 0, 1_500, accuracy: 0.001)
        XCTAssertEqual(status?.drawdown?.level, .ok)
    }

    func test_backtestTradesInLiveAccount_areIgnored_butBacktestAccountCountsItsOwn() {
        let live = makeAccount(daily: 500)
        makeTrade(live, day: 10, points: -30, isBacktest: true)
        let backtest = makeAccount(type: .backtest, daily: 500)
        let own = makeTrade(backtest, day: 10, points: -30, isBacktest: true)

        let all = try! context.fetch(FetchDescriptor<Trade>())
        let liveStatus = service.status(for: live, trades: all, now: date(10, 18), calendar: calendar)
        XCTAssertEqual(liveStatus?.dailyLoss?.used, 0)

        let backtestStatus = service.status(for: backtest, trades: all, now: date(10, 18), calendar: calendar)
        XCTAssertEqual(backtestStatus?.dailyLoss?.used ?? 0, -StatsService().metrics(for: own).netPnL, accuracy: 0.001)
        XCTAssertEqual(backtestStatus?.dailyLoss?.level, .breached)
    }

    func test_statuses_skipsArchivedAndGoalless() {
        let active = makeAccount(target: 1_000)
        let archived = makeAccount(target: 1_000)
        archived.isArchived = true
        _ = makeAccount()

        let statuses = service.statuses(accounts: [active, archived], trades: [], now: date(10), calendar: calendar)
        XCTAssertEqual(statuses.map(\.accountID), [active.id])
    }

    // MARK: - Maanddoel = kalendertotaal (bug: US$ 102 i.p.v. US$ 148)

    /// Uitgebreide trade zoals het formulier hem standaard opslaat: exit-prijs
    /// ingevuld, exit-tijd niet (schakelaar uit) → `exitDate == nil`.
    @discardableResult
    private func makeTradeWithoutExitTime(_ account: Account, month: Int, day: Int, hour: Int = 15, points: Double, commission: Double = 0) -> Trade {
        let trade = Trade(
            symbol: "MNQ", direction: .long, entryDate: date(month: month, day, hour), exitDate: nil,
            entryPrice: 20_000, exitPrice: 20_000 + points, quantity: 1, commission: commission,
            tickSize: 0.25, tickValue: 0.5, account: account
        )
        context.insert(trade)
        return trade
    }

    /// Situatie uit de bugmelding: 24 sep +$46 en 25 sep +$102. De kalender
    /// toont weektotaal $148; het maanddoel moet ook 148 zijn.
    func test_monthlyTarget_sumsAllTradesInMonth_likeCalendar() {
        let account = makeAccount(type: .live, target: 2_000)
        let first = makeTradeWithoutExitTime(account, month: 9, day: 24, points: 23)            // MNQ $2/pt → +$46
        let second = makeTrade(account, month: 9, day: 25, points: 5.1)                       // NQ $20/pt → +$102
        XCTAssertEqual(StatsService().metrics(for: first).netPnL, 46, accuracy: 0.001)
        XCTAssertEqual(StatsService().metrics(for: second).netPnL, 102, accuracy: 0.001)

        let now = date(month: 9, 26, 10)
        let status = service.status(for: account, trades: [first, second], now: now, calendar: calendar)
        XCTAssertEqual(status?.monthlyTarget?.current ?? 0, 148, accuracy: 0.001)
        XCTAssertEqual(status?.monthlyTarget?.fraction ?? 0, 148.0 / 2_000, accuracy: 0.0001)

        // Zelfde bron als de kalender: som van de dagaggregaten in september.
        let aggregation = CalendarAggregationService()
        let days = aggregation.dayAggregates(for: [first, second], calendar: calendar)
        XCTAssertEqual(days.values.reduce(0) { $0 + $1.netPnL }, 148, accuracy: 0.001)
        XCTAssertEqual(aggregation.netPnL(of: [first, second], periodOf: .month, containing: now, calendar: calendar), 148, accuracy: 0.001)
    }

    func test_monthlyTarget_lossesAndCostsReduceProgress() {
        let account = makeAccount(target: 2_000)
        let trades = [
            makeTrade(account, month: 9, day: 24, points: 10),                                  // +200
            makeTradeWithoutExitTime(account, month: 9, day: 25, points: -20, commission: 4)    // -40 - 4 = -44
        ]
        let status = service.status(for: account, trades: trades, now: date(month: 9, 26), calendar: calendar)
        XCTAssertEqual(status?.monthlyTarget?.current ?? 0, 156, accuracy: 0.001)
    }

    func test_monthlyTarget_negativeMonth_barIsEmpty() {
        let account = makeAccount(target: 2_000)
        let trades = [makeTrade(account, month: 9, day: 24, points: -10)]
        let status = service.status(for: account, trades: trades, now: date(month: 9, 26), calendar: calendar)
        XCTAssertEqual(status?.monthlyTarget?.current ?? 0, -200, accuracy: 0.001)
        XCTAssertEqual(status?.monthlyTarget?.fraction, 0)
    }

    /// Een trade om precies 00:00 op de 1e van de volgende maand hoort niet
    /// meer bij deze maand (eind exclusief).
    func test_monthlyTarget_monthBoundaryIsExclusive() {
        let account = makeAccount(target: 2_000)
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let trade = Trade(
            symbol: "NQ", direction: .long, entryDate: midnight.addingTimeInterval(-600), exitDate: midnight,
            entryPrice: 18_000, exitPrice: 18_010, quantity: 1, tickSize: 0.25, tickValue: 5, account: account
        )
        context.insert(trade)
        let september = service.status(for: account, trades: [trade], now: date(month: 9, 30), calendar: calendar)
        XCTAssertEqual(september?.monthlyTarget?.current, 0)
        let october = service.status(for: account, trades: [trade], now: date(month: 10, 2), calendar: calendar)
        XCTAssertEqual(october?.monthlyTarget?.current ?? 0, 200, accuracy: 0.001)
    }

    func test_monthlyTarget_usesUserTimeZone() {
        // 1 sep 01:30 in Amsterdam (CEST) = 31 aug 23:30 UTC: september voor de gebruiker.
        var amsterdam = Calendar(identifier: .gregorian)
        amsterdam.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let account = makeAccount(target: 2_000)
        let exit = amsterdam.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 1, minute: 30))!
        let trade = Trade(
            symbol: "NQ", direction: .long, entryDate: exit.addingTimeInterval(-300), exitDate: exit,
            entryPrice: 18_000, exitPrice: 18_010, quantity: 1, tickSize: 0.25, tickValue: 5, account: account
        )
        context.insert(trade)
        let now = amsterdam.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!
        XCTAssertEqual(service.status(for: account, trades: [trade], now: now, calendar: amsterdam)?.monthlyTarget?.current ?? 0, 200, accuracy: 0.001)
        // In UTC valt dezelfde trade nog in augustus.
        XCTAssertEqual(service.status(for: account, trades: [trade], now: now, calendar: calendar)?.monthlyTarget?.current, 0)
    }

    /// Zelfde fout gold voor de daily loss limit: een verlies zonder exit-tijd telde niet mee.
    func test_dailyLoss_countsTradesWithoutExitTime() {
        let account = makeAccount(daily: 500)
        makeTradeWithoutExitTime(account, month: 9, day: 26, hour: 9, points: -100)          // -$200
        let all = try! context.fetch(FetchDescriptor<Trade>())
        let status = service.status(for: account, trades: all, now: date(month: 9, 26, 18), calendar: calendar)
        XCTAssertEqual(status?.dailyLoss?.used ?? 0, 200, accuracy: 0.001)
    }
}
