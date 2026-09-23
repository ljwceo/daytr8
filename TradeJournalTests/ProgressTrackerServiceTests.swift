import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class ProgressTrackerServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let service = ProgressTrackerService()
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

    // MARK: - Helpers

    private func date(_ day: Int, _ hour: Int = 15, month: Int = 3) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// NQ-trade: +/- `points` punten = +/- $20 per punt.
    @discardableResult
    private func makeTrade(day: Int, hour: Int = 15, points: Double, account: Account? = nil, isBacktest: Bool = false) -> Trade {
        let entry = date(day, hour)
        let trade = Trade(
            symbol: "NQ", direction: .long, entryDate: entry, exitDate: entry.addingTimeInterval(300),
            entryPrice: 18_000, exitPrice: 18_000 + points, quantity: 1,
            tickSize: 0.25, tickValue: 5, isBacktest: isBacktest, account: account
        )
        context.insert(trade)
        return trade
    }

    @discardableResult
    private func makeRule(_ kind: DailyRuleKind, threshold: Double = 0, createdDay: Int = 1, sortOrder: Int = 0) -> DailyRule {
        let rule = DailyRule(name: kind.displayName, kind: kind, threshold: threshold, sortOrder: sortOrder, createdAt: date(createdDay, 0))
        context.insert(rule)
        return rule
    }

    private func evaluate(_ rules: [DailyRule], day: Int, trades: [Trade], journal: DailyJournal? = nil, checks: [DailyRuleCheck] = []) -> DayProgress {
        service.evaluate(rules: rules, on: date(day), dayTrades: trades, journal: journal, checks: checks, calendar: calendar)
    }

    // MARK: - Regelsoorten

    func test_maxTrades() {
        let rule = makeRule(.maxTrades, threshold: 2)
        let two = [makeTrade(day: 10, points: 5), makeTrade(day: 10, hour: 16, points: 5)]
        XCTAssertTrue(evaluate([rule], day: 10, trades: two).isPerfect)

        let three = two + [makeTrade(day: 10, hour: 17, points: 5)]
        let result = evaluate([rule], day: 10, trades: three)
        XCTAssertFalse(result.isPerfect)
        XCTAssertEqual(result.evaluations.first?.detail, "3 van max 2 trades")
    }

    func test_stopAfterLosses_violatedOnlyWhenTradingAfterLimit() {
        let rule = makeRule(.stopAfterLosses, threshold: 2)
        let lossLossStop = [makeTrade(day: 10, hour: 14, points: -5), makeTrade(day: 10, hour: 15, points: -5)]
        XCTAssertTrue(evaluate([rule], day: 10, trades: lossLossStop).isPerfect)

        let tradedOn = lossLossStop + [makeTrade(day: 10, hour: 16, points: 10)]
        XCTAssertFalse(evaluate([rule], day: 10, trades: tradedOn).isPerfect)

        // Verlies, winst, verlies: pas na het tweede verlies stoppen is prima.
        let mixed = [makeTrade(day: 11, hour: 14, points: -5), makeTrade(day: 11, hour: 15, points: 10), makeTrade(day: 11, hour: 16, points: -5)]
        XCTAssertTrue(evaluate([rule], day: 11, trades: mixed).isPerfect)
    }

    func test_maxDailyLoss() {
        let rule = makeRule(.maxDailyLoss, threshold: 200)
        // -10 punten = -$200 → precies op de grens is nog gevolgd.
        XCTAssertTrue(evaluate([rule], day: 10, trades: [makeTrade(day: 10, points: -10)]).isPerfect)
        XCTAssertFalse(evaluate([rule], day: 11, trades: [makeTrade(day: 11, points: -11)]).isPerfect)
    }

    func test_journalFilled() {
        let rule = makeRule(.journalFilled)
        XCTAssertFalse(evaluate([rule], day: 10, trades: [], journal: DailyJournal(date: date(10), mood: "scherp")).isPerfect)
        XCTAssertTrue(evaluate([rule], day: 10, trades: [], journal: DailyJournal(date: date(10), postMarketReview: "Plan gevolgd")).isPerfect)
    }

    func test_manualRule_usesCheckOfThatDay() {
        let rule = makeRule(.manual)
        let check = DailyRuleCheck(date: date(10, 0))
        context.insert(check)
        check.rule = rule
        let otherDay = DailyRuleCheck(date: date(11, 0))
        context.insert(otherDay)
        otherDay.rule = rule

        XCTAssertTrue(evaluate([rule], day: 10, trades: [], checks: [check, otherDay]).isPerfect)
        XCTAssertFalse(evaluate([rule], day: 12, trades: [makeTrade(day: 12, points: 1)], checks: [check, otherDay]).isPerfect)
    }

    func test_rulesCreatedLaterOrInactive_doNotApply() {
        let early = makeRule(.maxTrades, threshold: 5, createdDay: 1)
        let late = makeRule(.journalFilled, createdDay: 20)
        let inactive = makeRule(.manual)
        inactive.isActive = false

        let result = evaluate([early, late, inactive], day: 10, trades: [makeTrade(day: 10, points: 5)])
        XCTAssertEqual(result.evaluations.map(\.ruleID), [early.id])
    }

    func test_backtestTrades_areIgnored() {
        let rule = makeRule(.maxTrades, threshold: 1)
        let backtestAccount = Account(name: "BT", type: .backtest, startingBalance: 0)
        context.insert(backtestAccount)
        let trades = [
            makeTrade(day: 10, points: 5),
            makeTrade(day: 10, hour: 16, points: 5, isBacktest: true),
            makeTrade(day: 10, hour: 17, points: 5, account: backtestAccount)
        ]
        let result = evaluate([rule], day: 10, trades: trades)
        XCTAssertTrue(result.isPerfect)
        XCTAssertTrue(result.isTracked)
    }

    // MARK: - Meerdere dagen

    func test_progress_onlyTracksDaysWithActivity() {
        let rule = makeRule(.maxTrades, threshold: 3)
        let trades = [makeTrade(day: 10, points: 5), makeTrade(day: 12, points: 5)]
        let journal = DailyJournal(date: date(14, 0), preMarketPlan: "Bias bullish")
        context.insert(journal)

        let progress = service.progress(rules: [rule], trades: trades, journals: [journal], checks: [], calendar: calendar)
        XCTAssertEqual(Set(progress.keys), [date(10, 0), date(12, 0), date(14, 0)])

        let limited = service.progress(rules: [rule], trades: trades, journals: [journal], checks: [], in: date(11, 0)...date(13, 0), calendar: calendar)
        XCTAssertEqual(Array(limited.keys), [date(12, 0)])
    }

    func test_summary_streaksAndConsistency() {
        let rule = makeRule(.maxTrades, threshold: 1)
        // Dag 2, 3 perfect; dag 4 overtreden; dag 6, 9, 10 perfect (gaten = geen activiteit).
        var trades: [Trade] = []
        for day in [2, 3, 6, 9, 10] { trades.append(makeTrade(day: day, points: 5)) }
        trades.append(makeTrade(day: 4, hour: 14, points: 5))
        trades.append(makeTrade(day: 4, hour: 15, points: 5))

        let progress = service.progress(rules: [rule], trades: trades, journals: [], checks: [], calendar: calendar)
        let summary = service.summary(for: progress, today: date(10), calendar: calendar)
        XCTAssertEqual(summary.currentStreak, 3)
        XCTAssertEqual(summary.longestStreak, 3)
        XCTAssertEqual(summary.trackedDays, 6)
        XCTAssertEqual(summary.perfectDays, 5)
        XCTAssertEqual(summary.consistency ?? 0, 5.0 / 6.0, accuracy: 0.0001)
    }

    func test_summary_unfinishedToday_doesNotBreakStreak() {
        let rule = makeRule(.journalFilled)
        let yesterday = DailyJournal(date: date(9, 0), postMarketReview: "ok")
        context.insert(yesterday)
        // Vandaag al een trade, maar het journal is nog leeg.
        let trades = [makeTrade(day: 10, points: 5)]

        let progress = service.progress(rules: [rule], trades: trades, journals: [yesterday], checks: [], calendar: calendar)
        XCTAssertEqual(progress[date(10, 0)]?.isPerfect, false)
        XCTAssertEqual(service.summary(for: progress, today: date(10), calendar: calendar).currentStreak, 1)
        // Een dag later telt de gemiste dag wel als breuk.
        XCTAssertEqual(service.summary(for: progress, today: date(11), calendar: calendar).currentStreak, 0)
    }

    func test_summary_empty() {
        let summary = service.summary(for: [:], today: date(10), calendar: calendar)
        XCTAssertEqual(summary.currentStreak, 0)
        XCTAssertNil(summary.consistency)
    }
}
