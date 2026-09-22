import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class CSVExportServiceTests: XCTestCase {

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

    private func makeTrade() -> Trade {
        let account = Account(name: "Topstep, 50k", type: .propFirm, startingBalance: 50_000)
        context.insert(account)
        let confluence = Confluence(name: "IFVG", category: .pdArrays)
        context.insert(confluence)
        let trade = Trade(
            symbol: "NQ", direction: .short,
            entryDate: Date(timeIntervalSince1970: 1_733_409_000),
            exitDate: Date(timeIntervalSince1970: 1_733_409_600),
            entryPrice: 21_010, exitPrice: 21_000, quantity: 1,
            stopLoss: 21_020, commission: 2.5, fees: 1,
            tickSize: 0.25, tickValue: 5,
            rating: 4, notes: "Sweep PDH, \"mooie\" entry\ntweede regel",
            account: account
        )
        context.insert(trade)
        trade.confluences = [confluence]
        return trade
    }

    func test_csv_containsHeaderAndComputedFields() throws {
        let trade = makeTrade()
        let csv = CSVExportService().csv(for: [trade])
        let table = try CSVParser.parse(csv)

        XCTAssertEqual(table.headers, CSVExportService.headers)
        XCTAssertEqual(table.rows.count, 1)
        let row = table.rows[0]
        func value(_ header: String) -> String { row[CSVExportService.headers.firstIndex(of: header)!] }

        XCTAssertEqual(value("account"), "Topstep, 50k")
        XCTAssertEqual(value("direction"), "short")
        XCTAssertEqual(value("entry_time"), "2024-12-05T14:30:00Z")
        XCTAssertEqual(value("gross_pnl"), "200")         // 10 punten × $20
        XCTAssertEqual(value("net_pnl"), "196.5")
        XCTAssertEqual(value("r_multiple"), "0.9825")     // 196.5 / 200 risk
        XCTAssertEqual(value("confluences"), "IFVG")
        XCTAssertEqual(value("rating"), "4")
        XCTAssertEqual(value("notes"), "Sweep PDH, \"mooie\" entry\ntweede regel")
    }

    func test_openTradeHasEmptyResultColumns() throws {
        let trade = Trade(symbol: "ES", direction: .long, entryDate: Date(), entryPrice: 6_000, quantity: 1, tickSize: 0.25, tickValue: 12.5)
        context.insert(trade)
        let row = CSVExportService().row(for: trade)
        let index = CSVExportService.headers.firstIndex(of: "net_pnl")!
        XCTAssertEqual(row[index], "")
        XCTAssertEqual(row[CSVExportService.headers.firstIndex(of: "exit_time")!], "")
    }

    func test_number_formatting() {
        XCTAssertEqual(CSVExportService.number(21_000), "21000")
        XCTAssertEqual(CSVExportService.number(1.05120), "1.0512")
        XCTAssertEqual(CSVExportService.number(-0.5), "-0.5")
    }

    /// Een export moet via de "TradeJournal"-preset weer ingelezen kunnen
    /// worden, en een tweede keer als duplicaat herkend worden.
    func test_exportThenImport_roundTrip() throws {
        let trade = makeTrade()
        let csv = CSVExportService().csv(for: [trade])

        let table = try CSVParser.parse(csv)
        let preset = try XCTUnwrap(CSVImportPresets.detect(headers: table.headers))
        XCTAssertEqual(preset.id, "tradejournal")

        let service = CSVImportService()
        let known = CSVImportService.knownSymbols(instruments: [])
        let result = service.extract(from: table, mapping: preset.mapping(for: table.headers), knownSymbols: known)
        XCTAssertEqual(result.trades.count, 1)
        let imported = result.trades[0]
        XCTAssertEqual(imported.direction, .short)
        XCTAssertEqual(imported.entryDate, trade.entryDate)
        XCTAssertEqual(imported.exitPrice, 21_000)
        XCTAssertEqual(imported.stopLoss, 21_020)
        XCTAssertEqual(imported.commission, 2.5)
        XCTAssertEqual(imported.fees, 1)
        XCTAssertEqual(imported.notes, trade.notes)

        let preview = service.preview(result.trades, existingTrades: [trade], knownSymbols: known)
        XCTAssertEqual(preview.map(\.isDuplicate), [true])
    }
}
