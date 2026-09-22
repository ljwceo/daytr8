import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class ReportsViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var viewModel: ReportsViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        viewModel = ReportsViewModel()
    }

    override func tearDownWithError() throws {
        container = nil
        viewModel = nil
        try super.tearDownWithError()
    }

    @discardableResult
    private func makeTrade(
        symbol: String = "NQ",
        account: Account? = nil,
        entryDate: Date,
        entry: Double = 18_000,
        exit: Double = 18_010
    ) -> Trade {
        let trade = Trade(
            symbol: symbol,
            direction: .long,
            entryDate: entryDate,
            exitDate: entryDate.addingTimeInterval(600),
            entryPrice: entry,
            exitPrice: exit,
            quantity: 1,
            tickSize: 0.25,
            tickValue: 5.0,
            account: account
        )
        context.insert(trade)
        return trade
    }

    // MARK: - Primaire / secundaire filterset

    func test_primaryAndSecondaryFilters_areIndependent() {
        let now = Date()
        let nq = makeTrade(symbol: "NQ", entryDate: now)
        let es = makeTrade(symbol: "ES", entryDate: now)

        viewModel.primaryFilter.symbolFilter = "NQ"
        viewModel.secondaryFilter.symbolFilter = "ES"

        let trades = [nq, es]
        XCTAssertEqual(viewModel.primaryTrades(trades).map(\.symbol), ["NQ"])
        XCTAssertEqual(viewModel.secondaryTrades(trades).map(\.symbol), ["ES"])
    }

    // MARK: - Groeperen

    func test_groupResults_bySymbol_dispatchesToAggregationService() {
        let now = Date()
        makeTrade(symbol: "NQ", entryDate: now)
        makeTrade(symbol: "ES", entryDate: now)

        let trades = try! context.fetch(FetchDescriptor<Trade>())
        let results = viewModel.groupResults(for: .symbol, trades: trades)

        XCTAssertEqual(Set(results.map(\.label)), ["NQ", "ES"])
    }

    func test_groupResults_confluenceCombinations_ignoresSortSettings() {
        // Combinaties worden altijd op expectancy gesorteerd, ongeacht sortKey/sortAscending.
        viewModel.sortKey = .tradeCount
        viewModel.sortAscending = true

        let a = Confluence(name: "A", category: .other)
        let b = Confluence(name: "B", category: .other)
        context.insert(a)
        context.insert(b)
        let now = Date()
        let trade1 = makeTrade(entryDate: now)
        trade1.confluences = [a, b]
        let trade2 = makeTrade(entryDate: now)
        trade2.confluences = [a, b]

        let trades = try! context.fetch(FetchDescriptor<Trade>())
        let results = viewModel.groupResults(for: .confluenceCombinations, trades: trades)

        XCTAssertEqual(results.first?.label, "A + B")
    }

    // MARK: - Sortering

    func test_groupResults_sortsBySelectedKeyDescendingByDefault() {
        let now = Date()
        makeTrade(symbol: "NQ", entryDate: now, exit: 18_050)  // grote winst
        makeTrade(symbol: "ES", entryDate: now, exit: 17_990)  // klein verlies

        let trades = try! context.fetch(FetchDescriptor<Trade>())
        viewModel.sortKey = .netPnL
        viewModel.sortAscending = false

        let results = viewModel.groupResults(for: .symbol, trades: trades)
        XCTAssertEqual(results.first?.label, "NQ")
    }

    func test_groupResults_sortAscending_reversesOrder() {
        let now = Date()
        makeTrade(symbol: "NQ", entryDate: now, exit: 18_050)
        makeTrade(symbol: "ES", entryDate: now, exit: 17_990)

        let trades = try! context.fetch(FetchDescriptor<Trade>())
        viewModel.sortKey = .netPnL
        viewModel.sortAscending = true

        let results = viewModel.groupResults(for: .symbol, trades: trades)
        XCTAssertEqual(results.first?.label, "ES")
    }

    // MARK: - Tab-metadata

    func test_isUserSortable_falseForFixedOrderTabs() {
        XCTAssertFalse(ReportsViewModel.Tab.dayOfWeek.isUserSortable)
        XCTAssertFalse(ReportsViewModel.Tab.hourOfDay.isUserSortable)
        XCTAssertFalse(ReportsViewModel.Tab.duration.isUserSortable)
        XCTAssertFalse(ReportsViewModel.Tab.rating.isUserSortable)
        XCTAssertFalse(ReportsViewModel.Tab.confluenceCombinations.isUserSortable)
        XCTAssertTrue(ReportsViewModel.Tab.confluence.isUserSortable)
        XCTAssertTrue(ReportsViewModel.Tab.playbook.isUserSortable)
    }
}
