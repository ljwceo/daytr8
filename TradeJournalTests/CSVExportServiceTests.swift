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

    // MARK: - Round-trip eigen export (bug: import van eigen export werkte niet)

    /// Exporteert `trades`, wist het journal (zoals na een herinstallatie) en
    /// importeert het bestand weer met auto-detectie.
    private func exportWipeAndImport(_ trades: [Trade], accounts: [Account]) throws -> (csv: String, created: [Trade]) {
        let csv = CSVExportService().csv(for: trades)
        for trade in trades { context.delete(trade) }
        try context.save()

        let table = try CSVParser.parse(csv)
        let preset = try XCTUnwrap(CSVImportPresets.detectOrGeneric(headers: table.headers))
        XCTAssertEqual(preset.id, "tradejournal")
        let mapping = preset.mapping(for: table.headers, timeZoneIdentifier: "Europe/Amsterdam")
        let service = CSVImportService()
        let known = CSVImportService.knownSymbols(instruments: [])
        let result = service.extract(from: table, mapping: mapping, knownSymbols: known)
        XCTAssertEqual(result.issues, [])
        let preview = service.preview(result.trades, existingTrades: [], knownSymbols: known)
        XCTAssertTrue(preview.allSatisfy { !$0.isDuplicate })
        let created = service.commit(preview, includeDuplicates: false, account: nil, accounts: accounts, instruments: [], in: context)
        return (csv, created)
    }

    func test_roundTrip_quickDetailedAndBrokerTrades_keepPnLAccountAndID() throws {
        let stats = StatsService()
        let account = Account(name: "Live account", type: .live, startingBalance: 10_000, monthlyProfitTarget: 2_000)
        context.insert(account)

        // 1. Snelle invoer: alleen resultaat, geen prijzen.
        let quick = Trade(symbol: "MNQ", direction: .long, entryDate: Date(timeIntervalSince1970: 1_790_000_000),
                          exitDate: Date(timeIntervalSince1970: 1_790_000_000), entryPrice: 0, quantity: 1,
                          tickSize: 0.25, tickValue: 0.5, account: account, manualNetPnL: 46)
        // 2. Uitgebreid met prijzen, zonder exit-tijd.
        let detailed = Trade(symbol: "NQ", direction: .long, entryDate: Date(timeIntervalSince1970: 1_790_090_000),
                             entryPrice: 20_000, exitPrice: 20_005.1, quantity: 1, commission: 0,
                             tickSize: 0.25, tickValue: 5, account: account)
        // 3. Uitgebreid met afwijkend broker-resultaat.
        let broker = Trade(symbol: "ES", direction: .short, entryDate: Date(timeIntervalSince1970: 1_790_100_000),
                           exitDate: Date(timeIntervalSince1970: 1_790_100_600), entryPrice: 6_000, exitPrice: 5_990,
                           quantity: 1, tickSize: 0.25, tickValue: 12.5, account: account, manualNetPnL: 495.2)
        for trade in [quick, detailed, broker] { context.insert(trade) }
        let originals = [quick, detailed, broker].map { (id: $0.id, net: stats.metrics(for: $0).netPnL, entry: $0.entryDate) }
        XCTAssertEqual(originals.map(\.net).reduce(0, +), 46 + 102 + 495.2, accuracy: 0.001)

        let (_, created) = try exportWipeAndImport([quick, detailed, broker], accounts: [account])
        XCTAssertEqual(created.count, 3)

        for original in originals {
            let trade = try XCTUnwrap(created.first { $0.id == original.id }, "trade-id blijft behouden")
            let metrics = stats.metrics(for: trade)
            XCTAssertNotEqual(metrics.outcome, .open)
            XCTAssertEqual(metrics.netPnL, original.net, accuracy: 0.001)
            XCTAssertEqual(trade.entryDate, original.entry)
            XCTAssertEqual(trade.account?.id, account.id)
        }
        // Uitgebreide trade blijft uit prijzen rekenen (geen handmatig resultaat).
        XCTAssertNil(created.first { $0.id == originals[1].id }?.manualNetPnL)

        // Maanddoel telt alle drie mee.
        let goal = GoalsService().status(for: account, trades: created, now: Date(timeIntervalSince1970: 1_790_100_600))
        XCTAssertEqual(goal?.monthlyTarget?.current ?? 0, 46 + 102 + 495.2, accuracy: 0.001)
    }

    func test_roundTrip_reimportSameFile_isAllDuplicates() throws {
        let trade = makeTrade()
        let csv = CSVExportService().csv(for: [trade])
        let table = try CSVParser.parse(csv)
        let preset = try XCTUnwrap(CSVImportPresets.detect(headers: table.headers))
        let service = CSVImportService()
        let known = CSVImportService.knownSymbols(instruments: [])
        var imported = service.extract(from: table, mapping: preset.mapping(for: table.headers), knownSymbols: known).trades
        // Zelfs met een verschoven entry-tijd herkent de trade-id het duplicaat.
        imported[0].entryDate = imported[0].entryDate.addingTimeInterval(60)
        let preview = service.preview(imported, existingTrades: [trade], knownSymbols: known)
        XCTAssertEqual(preview.map(\.isDuplicate), [true])
        XCTAssertEqual(service.commit(preview, includeDuplicates: false, account: nil, instruments: [], in: context).count, 0)

        // "Duplicaten ook importeren": nieuwe id, geen botsing.
        let forced = service.commit(preview, includeDuplicates: true, account: nil, instruments: [], in: context)
        XCTAssertEqual(forced.count, 1)
        XCTAssertNotEqual(forced[0].id, trade.id)
    }

    /// Europese Excel-variant: puntkomma, decimale komma, Nederlandse kolomnamen,
    /// datum met maandnaam — herkend via de generieke preset.
    func test_genericPreset_semicolonDecimalCommaDutchHeaders() throws {
        let csv = """
        Symbool;Richting;Aantal;Datum;Instapprijs;Uitstapprijs;Commissie;Netto
        MNQZ26;Long;1;24 sep 2026 15:31;20000,25;20023,25;1,24;44,76
        MNQZ26;Short;2;25-09-2026 16:02;20100;20080;2,48;77,52
        ;Long;1;25-09-2026 16:30;1;2;0;1
        """
        let table = try CSVParser.parse(csv)
        XCTAssertEqual(table.delimiter, ";")
        XCTAssertNil(CSVImportPresets.detect(headers: table.headers))
        let preset = try XCTUnwrap(CSVImportPresets.detectOrGeneric(headers: table.headers))
        XCTAssertEqual(preset.id, "generic")
        var mapping = preset.mapping(for: table.headers, timeZoneIdentifier: "UTC")
        mapping.dateOrder = .dayFirst
        XCTAssertEqual(mapping.validationErrors, [])

        let service = CSVImportService()
        let result = service.extract(from: table, mapping: mapping, knownSymbols: CSVImportService.knownSymbols(instruments: []))
        XCTAssertEqual(result.trades.count, 2)
        XCTAssertEqual(result.issues.map(\.row), [3])      // geen symbool → gemarkeerd met reden
        XCTAssertEqual(result.trades[0].symbol, "MNQ")       // MNQZ26 → doorlopend contract
        XCTAssertEqual(result.trades[0].entryPrice, 20_000.25)
        XCTAssertEqual(result.trades[0].commission, 1.24)
        XCTAssertEqual(result.trades[1].direction, .short)
        XCTAssertEqual(result.trades[1].reportedNetPnL, 77.52)
    }
}
