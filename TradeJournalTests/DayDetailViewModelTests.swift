import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class DayDetailViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var calendar: Calendar { Calendar.current }

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
    private func makeTrade(entryDate: Date, exitDate: Date? = nil) -> Trade {
        let trade = Trade(
            symbol: "NQ",
            direction: .long,
            entryDate: entryDate,
            exitDate: exitDate,
            entryPrice: 18_000,
            exitPrice: exitDate == nil ? nil : 18_010,
            quantity: 1,
            tickSize: 0.25,
            tickValue: 5.0
        )
        context.insert(trade)
        return trade
    }

    // MARK: - Filteren op dag

    func test_trades_filtersToTradesClosedOrOpenedOnThatDay() {
        let day = calendar.startOfDay(for: Date())
        let onDay = makeTrade(entryDate: day.addingTimeInterval(3600), exitDate: day.addingTimeInterval(4000))
        let otherDay = calendar.date(byAdding: .day, value: -1, to: day)!
        makeTrade(entryDate: otherDay, exitDate: otherDay.addingTimeInterval(600))

        let viewModel = DayDetailViewModel(date: day, journal: nil)
        let allTrades = try! context.fetch(FetchDescriptor<Trade>())
        let result = viewModel.trades(from: allTrades, calendar: calendar)

        XCTAssertEqual(result.map(\.id), [onDay.id])
    }

    func test_intradayEquityPoints_isCumulative() {
        let day = calendar.startOfDay(for: Date())
        let first = makeTrade(entryDate: day.addingTimeInterval(3600), exitDate: day.addingTimeInterval(3700))
        let second = makeTrade(entryDate: day.addingTimeInterval(7200), exitDate: day.addingTimeInterval(7300))

        let viewModel = DayDetailViewModel(date: day, journal: nil)
        let points = viewModel.intradayEquityPoints(for: [first, second])

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].value, 200, accuracy: 0.01)
        XCTAssertEqual(points[1].value, 400, accuracy: 0.01)
    }

    // MARK: - Journal opslaan

    func test_saveJournal_doesNotInsertWhenDraftIsEmptyAndNoExistingJournal() {
        let viewModel = DayDetailViewModel(date: Date(), journal: nil)
        let result = viewModel.saveJournal(existing: nil, in: context)
        XCTAssertNil(result)
    }

    func test_saveJournal_insertsNewJournalWhenDraftHasContent() {
        let date = calendar.startOfDay(for: Date())
        let viewModel = DayDetailViewModel(date: date, journal: nil)
        viewModel.journalDraft.dailyBias = "Bullish boven PDH"
        viewModel.journalDraft.dayRating = 8

        let journal = viewModel.saveJournal(existing: nil, in: context)

        XCTAssertNotNil(journal)
        XCTAssertEqual(journal?.dailyBias, "Bullish boven PDH")
        XCTAssertEqual(journal?.dayRating, 8)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyJournal>()), 1)
    }

    func test_saveJournal_updatesExistingJournal() {
        let date = calendar.startOfDay(for: Date())
        let existing = DailyJournal(date: date, dailyBias: "Neutral")
        context.insert(existing)

        let viewModel = DayDetailViewModel(date: date, journal: existing)
        viewModel.journalDraft.dailyBias = "Bearish onder PDL"

        let journal = viewModel.saveJournal(existing: existing, in: context)

        XCTAssertEqual(journal?.id, existing.id)
        XCTAssertEqual(journal?.dailyBias, "Bearish onder PDL")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyJournal>()), 1)
    }

    func test_resetDraft_reflectsSuppliedJournal() {
        let journal = DailyJournal(date: Date(), preMarketPlan: "Wacht op sweep", dayRating: 5)
        let viewModel = DayDetailViewModel(date: Date(), journal: nil)

        viewModel.resetDraft(from: journal)

        XCTAssertEqual(viewModel.journalDraft.preMarketPlan, "Wacht op sweep")
        XCTAssertEqual(viewModel.journalDraft.dayRating, 5)
    }
}
