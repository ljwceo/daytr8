import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class ReportAggregationServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let service = ReportAggregationService()

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
        symbol: String = "NQ",
        direction: TradeDirection = .long,
        entryDate: Date,
        exitDate: Date? = nil,
        entry: Double = 18_000,
        exit: Double? = 18_010,
        playbook: Playbook? = nil,
        confluences: [Confluence] = [],
        tags: [Tag] = [],
        mistakes: [Mistake] = [],
        emotionBefore: String = "",
        emotionAfter: String = "",
        rating: Int = 0
    ) -> Trade {
        let trade = Trade(
            symbol: symbol,
            direction: direction,
            entryDate: entryDate,
            exitDate: exit == nil ? nil : (exitDate ?? entryDate.addingTimeInterval(600)),
            entryPrice: entry,
            exitPrice: exit,
            quantity: 1,
            tickSize: 0.25,
            tickValue: 5.0,
            emotionBefore: emotionBefore,
            emotionAfter: emotionAfter,
            rating: rating,
            playbook: playbook
        )
        trade.confluences = confluences
        trade.tags = tags
        trade.mistakes = mistakes
        context.insert(trade)
        return trade
    }

    // MARK: - Confluence

    func test_byConfluence_groupsTradesThatShareAConfluence() {
        let sweep = Confluence(name: "Sweep PDL", category: .liquidity)
        let ifvg = Confluence(name: "IFVG", category: .pdArrays)
        context.insert(sweep)
        context.insert(ifvg)

        let now = Date()
        makeTrade(entryDate: now, exit: 18_010, confluences: [sweep])
        makeTrade(entryDate: now, exit: 17_990, confluences: [sweep, ifvg])
        makeTrade(entryDate: now, exit: 18_005, confluences: [ifvg])

        let results = service.byConfluence(allTrades())

        let sweepResult = results.first { $0.label == "Sweep PDL" }
        let ifvgResult = results.first { $0.label == "IFVG" }
        XCTAssertEqual(sweepResult?.statistics.tradeCount, 2)
        XCTAssertEqual(ifvgResult?.statistics.tradeCount, 2)
    }

    func test_byConfluence_tradeWithoutConfluencesIsExcluded() {
        let now = Date()
        makeTrade(entryDate: now)
        let results = service.byConfluence(allTrades())
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Confluence combinations

    func test_byConfluenceCombination_ranksByExpectancyAndFiltersByMinCount() {
        let sweep = Confluence(name: "Sweep PDL", category: .liquidity)
        let ifvg = Confluence(name: "IFVG", category: .pdArrays)
        let killzone = Confluence(name: "NY AM killzone", category: .time)
        context.insert(sweep)
        context.insert(ifvg)
        context.insert(killzone)

        let now = Date()
        // Sweep + IFVG: twee winnende trades → hoge expectancy.
        makeTrade(entryDate: now, exit: 18_020, confluences: [sweep, ifvg])
        makeTrade(entryDate: now, exit: 18_020, confluences: [sweep, ifvg])
        // Sweep + killzone: één trade → onder minTradeCount, moet wegvallen.
        makeTrade(entryDate: now, exit: 17_990, confluences: [sweep, killzone])

        let results = service.byConfluenceCombination(allTrades(), minTradeCount: 2)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.label, "IFVG + Sweep PDL")
        XCTAssertEqual(results.first?.statistics.tradeCount, 2)
    }

    func test_byConfluenceCombination_sortedDescendingByExpectancy() {
        let a = Confluence(name: "A", category: .other)
        let b = Confluence(name: "B", category: .other)
        let c = Confluence(name: "C", category: .other)
        context.insert(a)
        context.insert(b)
        context.insert(c)

        let now = Date()
        makeTrade(entryDate: now, exit: 18_050, confluences: [a, b])
        makeTrade(entryDate: now, exit: 18_050, confluences: [a, b])
        makeTrade(entryDate: now, exit: 17_960, confluences: [a, c])
        makeTrade(entryDate: now, exit: 17_960, confluences: [a, c])

        let results = service.byConfluenceCombination(allTrades(), minTradeCount: 2)
        XCTAssertEqual(results.map(\.label), ["A + B", "A + C"])
    }

    // MARK: - Playbook / symbool / richting / sessie

    func test_byPlaybook_excludesTradesWithoutPlaybook() {
        let playbook = Playbook(name: "ICT AM")
        context.insert(playbook)
        let now = Date()
        makeTrade(entryDate: now, playbook: playbook)
        makeTrade(entryDate: now)

        let results = service.byPlaybook(allTrades())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.label, "ICT AM")
        XCTAssertEqual(results.first?.statistics.tradeCount, 1)
    }

    func test_bySymbol_groupsExactMatches() {
        let now = Date()
        makeTrade(symbol: "NQ", entryDate: now)
        makeTrade(symbol: "ES", entryDate: now)
        makeTrade(symbol: "NQ", entryDate: now)

        let results = service.bySymbol(allTrades())
        let nq = results.first { $0.label == "NQ" }
        XCTAssertEqual(nq?.statistics.tradeCount, 2)
        XCTAssertEqual(results.count, 2)
    }

    func test_byDirection_splitsLongAndShort() {
        let now = Date()
        makeTrade(direction: .long, entryDate: now)
        makeTrade(direction: .short, entryDate: now, entry: 18_000, exit: 17_990)

        let results = service.byDirection(allTrades())
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.label == "Long" })
        XCTAssertTrue(results.contains { $0.label == "Short" })
    }

    // MARK: - Dag van de week / uur van de dag

    func test_byDayOfWeek_isSortedMondayToSunday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // 2024-01-01 = maandag, 2024-01-07 = zondag (UTC).
        let monday = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 10))!
        let sunday = calendar.date(from: DateComponents(year: 2024, month: 1, day: 7, hour: 10))!
        makeTrade(entryDate: sunday, exitDate: sunday)
        makeTrade(entryDate: monday, exitDate: monday)

        let results = service.byDayOfWeek(allTrades(), calendar: calendar)
        XCTAssertEqual(results.map(\.label), ["Maandag", "Zondag"])
    }

    func test_byHourOfDay_groupsByEntryHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let nineAM = calendar.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 9))!
        let twoPM = calendar.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 14))!
        makeTrade(entryDate: nineAM)
        makeTrade(entryDate: twoPM)

        let results = service.byHourOfDay(allTrades(), calendar: calendar)
        XCTAssertEqual(results.map(\.label), ["09:00", "14:00"])
    }

    // MARK: - Trade-duur

    func test_byDuration_bucketsByLengthAndExcludesOpenTrades() {
        let now = Date()
        makeTrade(entryDate: now, exitDate: now.addingTimeInterval(2 * 60))  // < 5 min
        makeTrade(entryDate: now, exitDate: now.addingTimeInterval(20 * 60))  // 15-30 min
        makeTrade(entryDate: now, exit: nil)  // open, moet worden uitgesloten

        let results = service.byDuration(allTrades())
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.label == "< 5 min" })
        XCTAssertTrue(results.contains { $0.label == "15–30 min" })
    }

    // MARK: - Tags & mistakes

    func test_byTag_groupsTrades() {
        let tag = Tag(name: "Revenge trade")
        context.insert(tag)
        let now = Date()
        makeTrade(entryDate: now, tags: [tag])
        makeTrade(entryDate: now)

        let results = service.byTag(allTrades())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.statistics.tradeCount, 1)
    }

    func test_byMistake_showsNetPnLCostOfEachMistake() {
        let mistake = Mistake(name: "Te vroege entry")
        context.insert(mistake)
        let now = Date()
        makeTrade(entryDate: now, exit: 17_950, mistakes: [mistake])  // verlies

        let results = service.byMistake(allTrades())
        XCTAssertEqual(results.count, 1)
        XCTAssertLessThan(results.first?.statistics.netPnL ?? 0, 0)
    }

    // MARK: - Emotie & rating

    func test_byEmotionBefore_excludesEmptyValues() {
        let now = Date()
        makeTrade(entryDate: now, emotionBefore: "Rustig")
        makeTrade(entryDate: now, emotionBefore: "")

        let results = service.byEmotionBefore(allTrades())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.label, "Rustig")
    }

    func test_byRating_sortedAscendingAndExcludesUnrated() {
        let now = Date()
        makeTrade(entryDate: now, rating: 4)
        makeTrade(entryDate: now, rating: 2)
        makeTrade(entryDate: now, rating: 0)

        let results = service.byRating(allTrades())
        XCTAssertEqual(results.map(\.label), ["2 ★", "4 ★"])
    }

    // MARK: - Helper

    private func allTrades() -> [Trade] {
        (try? context.fetch(FetchDescriptor<Trade>())) ?? []
    }
}
