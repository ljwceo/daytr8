import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class NotebookViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var viewModel: NotebookViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        viewModel = NotebookViewModel(calendar: calendar)
    }

    override func tearDownWithError() throws {
        container = nil
        viewModel = nil
        try super.tearDownWithError()
    }

    private func makeTrade(_ symbol: String) -> Trade {
        let trade = Trade(symbol: symbol, direction: .long, entryDate: Date(timeIntervalSince1970: 1_790_000_000), entryPrice: 100, quantity: 1)
        context.insert(trade)
        return trade
    }

    func test_save_newNote_linksTradesAndDay() throws {
        let nq = makeTrade("NQ")
        _ = makeTrade("ES")
        var draft = NotebookViewModel.Draft(linkedDate: Date(timeIntervalSince1970: 1_790_078_400), tradeIDs: [nq.id])
        draft.title = " Les "
        draft.body = "Niet chasen na een sweep."

        let note = try XCTUnwrap(viewModel.save(draft, existing: nil, allTrades: [nq], in: context, now: Date(timeIntervalSince1970: 1_790_100_000)))
        XCTAssertEqual(note.title, "Les")
        XCTAssertEqual(note.trades.map(\.id), [nq.id])
        XCTAssertEqual(nq.notebookNotes.map(\.id), [note.id])
        // Gekoppelde dag op middernacht.
        XCTAssertEqual(note.linkedDate, Date(timeIntervalSince1970: 1_790_035_200))
        XCTAssertEqual(viewModel.notes(linkedTo: Date(timeIntervalSince1970: 1_790_078_400), from: [note]).count, 1)
        XCTAssertEqual(viewModel.notes(for: nq).map(\.id), [note.id])
    }

    func test_save_emptyNewNote_isIgnored() throws {
        XCTAssertNil(viewModel.save(NotebookViewModel.Draft(), existing: nil, allTrades: [], in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotebookNote>()), 0)
    }

    func test_save_existing_unlinksTrades() throws {
        let nq = makeTrade("NQ")
        let note = NotebookNote(title: "Les")
        context.insert(note)
        note.trades = [nq]

        var draft = NotebookViewModel.Draft(from: note)
        draft.tradeIDs = []
        viewModel.save(draft, existing: note, allTrades: [nq], in: context)
        XCTAssertTrue(note.trades.isEmpty)
    }

    func test_filtered_searchPinnedAndOrder() {
        let old = NotebookNote(title: "Oud", body: "FVG entry", updatedAt: Date(timeIntervalSince1970: 100))
        let new = NotebookNote(title: "Nieuw", body: "Geduld", updatedAt: Date(timeIntervalSince1970: 300))
        let pinned = NotebookNote(title: "Regels", body: "Max 2 verliezen", isPinned: true, updatedAt: Date(timeIntervalSince1970: 50))
        for note in [old, new, pinned] { context.insert(note) }
        let es = makeTrade("ES")
        old.trades = [es]

        XCTAssertEqual(viewModel.filtered([old, new, pinned]).map(\.title), ["Regels", "Nieuw", "Oud"])

        viewModel.searchText = "fvg"
        XCTAssertEqual(viewModel.filtered([old, new, pinned]).map(\.title), ["Oud"])
        viewModel.searchText = "ES"
        XCTAssertEqual(viewModel.filtered([old, new, pinned]).map(\.title), ["Oud"])

        viewModel.searchText = ""
        viewModel.pinnedOnly = true
        XCTAssertEqual(viewModel.filtered([old, new, pinned]).map(\.title), ["Regels"])
    }

    func test_displayTitle_fallsBackToFirstLine() {
        XCTAssertEqual(NotebookNote(title: "", body: "\nEerste regel\nTweede").displayTitle, "Eerste regel")
        XCTAssertEqual(NotebookNote(title: "  ").displayTitle, "Naamloze notitie")
    }
}
