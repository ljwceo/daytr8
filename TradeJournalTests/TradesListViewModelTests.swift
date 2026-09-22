import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class TradesListViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

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
        entry: Double = 100,
        exit: Double? = 110,
        entryDate: Date = Date(timeIntervalSince1970: 1_720_000_000),
        exitDate: Date? = Date(timeIntervalSince1970: 1_720_003_600),
        notes: String = "",
        playbookName: String? = nil,
        tagName: String? = nil
    ) -> Trade {
        let trade = Trade(
            symbol: symbol,
            direction: direction,
            entryDate: entryDate,
            exitDate: exit == nil ? nil : exitDate,
            entryPrice: entry,
            exitPrice: exit,
            quantity: 1,
            tickSize: 1,
            tickValue: 1,
            notes: notes
        )
        context.insert(trade)
        if let playbookName {
            let playbook = Playbook(name: playbookName)
            context.insert(playbook)
            trade.playbook = playbook
        }
        if let tagName {
            let tag = Tag(name: tagName)
            context.insert(tag)
            trade.tags = [tag]
        }
        return trade
    }

    // MARK: - Filters

    func test_quickFilter_open_keepsOnlyOpenTrades() {
        let viewModel = TradesListViewModel()
        let open = makeTrade(exit: nil, exitDate: nil)
        let closed = makeTrade(exit: 110)

        viewModel.quickFilter = .open
        let result = viewModel.filteredAndSorted([open, closed])

        XCTAssertEqual(result.map(\.id), [open.id])
    }

    func test_quickFilter_wins_keepsOnlyWinningTrades() {
        let viewModel = TradesListViewModel()
        let win = makeTrade(entry: 100, exit: 110)
        let loss = makeTrade(entry: 100, exit: 90)

        viewModel.quickFilter = .wins
        let result = viewModel.filteredAndSorted([win, loss])

        XCTAssertEqual(result.map(\.id), [win.id])
    }

    func test_directionFilter_keepsOnlyMatchingDirection() {
        let viewModel = TradesListViewModel()
        let long = makeTrade(direction: .long)
        let short = makeTrade(direction: .short)

        viewModel.directionFilter = .short
        let result = viewModel.filteredAndSorted([long, short])

        XCTAssertEqual(result.map(\.id), [short.id])
    }

    func test_search_matchesSymbolPlaybookAndTag() {
        let viewModel = TradesListViewModel()
        let bySymbol = makeTrade(symbol: "GBPUSD")
        let byPlaybook = makeTrade(symbol: "NQ", playbookName: "Silver Bullet")
        let byTag = makeTrade(symbol: "ES", tagName: "A+")
        let unrelated = makeTrade(symbol: "CL")

        viewModel.searchText = "silver"
        XCTAssertEqual(viewModel.filteredAndSorted([bySymbol, byPlaybook, byTag, unrelated]).map(\.id), [byPlaybook.id])

        viewModel.searchText = "gbpusd"
        XCTAssertEqual(viewModel.filteredAndSorted([bySymbol, byPlaybook, byTag, unrelated]).map(\.id), [bySymbol.id])

        viewModel.searchText = "a+"
        XCTAssertEqual(viewModel.filteredAndSorted([bySymbol, byPlaybook, byTag, unrelated]).map(\.id), [byTag.id])
    }

    // MARK: - Sortering

    func test_sortOption_pnlDescending_ordersLargestWinFirst() {
        let viewModel = TradesListViewModel()
        let bigWin = makeTrade(entry: 100, exit: 150)
        let smallWin = makeTrade(entry: 100, exit: 110)
        let loss = makeTrade(entry: 100, exit: 80)

        viewModel.sortOption = .pnlDescending
        let result = viewModel.filteredAndSorted([smallWin, loss, bigWin])

        XCTAssertEqual(result.map(\.id), [bigWin.id, smallWin.id, loss.id])
    }

    func test_sortOption_dateAscending_ordersOldestFirst() {
        let viewModel = TradesListViewModel()
        let older = makeTrade(entryDate: Date(timeIntervalSince1970: 1_000), exit: nil, exitDate: nil)
        let newer = makeTrade(entryDate: Date(timeIntervalSince1970: 2_000), exit: nil, exitDate: nil)

        viewModel.sortOption = .dateAscending
        let result = viewModel.filteredAndSorted([newer, older])

        XCTAssertEqual(result.map(\.id), [older.id, newer.id])
    }
}
