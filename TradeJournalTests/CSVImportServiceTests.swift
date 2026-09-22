import XCTest
import SwiftData
@testable import TradeJournal

/// Parser-/import-tests met een tekstfixture per broker-preset, zodat
/// kolomnamen en notaties niet stilletjes stukgaan.
@MainActor
final class CSVImportServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let service = CSVImportService()
    private let known = CSVImportService.knownSymbols(instruments: [])

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    static let tradovatePerformance = """
    symbol,_priceFormat,_priceFormatType,_tickSize,buyFillId,sellFillId,qty,buyPrice,sellPrice,pnl,boughtTimestamp,soldTimestamp,duration
    MNQZ4,-2,0,0.25,1001,1002,2,21000.25,21010.75,$42.00,12/05/2024 09:31:22,12/05/2024 09:35:10,3min 48sec
    MNQZ4,-2,0,0.25,1004,1003,1,21030.00,21020.00,$(20.00),12/05/2024 10:02:00,12/05/2024 10:00:00,2min
    """

    static let tradovateOrders = """
    orderId,Account,B/S,Contract,Product,avgPrice,filledQty,Fill Time,Status,Quantity,Type
    1,DEMO1, Buy,NQZ4,NQ,21000.00,1,12/05/2024 09:30:05,Filled,1,Market
    2,DEMO1, Sell,NQZ4,NQ,21005.50,1,12/05/2024 09:40:00,Filled,1,Limit
    3,DEMO1, Sell,NQZ4,NQ,,0,,Canceled,1,Stop
    """

    static let ninjaTraderTrades = """
    Trade number,Instrument,Account,Strategy,Market pos.,Qty,Entry price,Exit price,Entry time,Exit time,Entry name,Exit name,Profit,Cum. net profit,Commission,MAE,MFE,ETD,Bars
    1,ES 12-24,Sim101,,Short,2,6050.25,6045.75,12/5/2024 9:45:12 AM,12/5/2024 10:01:03 AM,Entry,Exit,$450.00,$450.00,$4.30,$125.00,$500.00,$50.00,3
    """

    static let ninjaTraderExecutions = """
    Instrument,Action,Quantity,Price,Time,ID,E/X,Position,Order ID,Name,Commission,Rate,Account,Connection
    NQ 12-24,Buy,1,21000.25,12/5/2024 9:30:01 AM,a1,Entry,1 L,o1,Entry,$2.15,1,Sim101,Sim
    NQ 12-24,Sell,1,21004.25,12/5/2024 9:33:00 AM,a2,Exit,-,o2,Exit,$2.15,1,Sim101,Sim
    """

    static let topstepX = """
    Id,ContractName,EnteredAt,ExitedAt,EntryPrice,ExitPrice,Fees,PnL,Size,Type,TradeDay,TradeDuration,Commissions
    12345,MNQZ4,12/05/2024 09:31:22 -05:00,12/05/2024 09:35:10 -05:00,21000.25,20990.25,0.74,-20.00,1,Long,12/05/2024 00:00:00 -06:00,00:03:48,
    """

    static let metaTrader = """
    Time,Position,Symbol,Type,Volume,Price,S / L,T / P,Time,Price,Commission,Swap,Profit
    2024.12.05 14:31:22,5001,EURUSD,buy,0.50,1.05120,1.05020,1.05320,2024.12.05 15:02:10,1.05220,-3.50,0.00,50.00
    2024.12.05 16:00:00,5002,GBPUSD.a,sell,1.00,1.27000,,,2024.12.05 16:30:00,1.27100,-7.00,0.00,-100.00
    """

    static let tradingView = """
    Symbol,Side,Type,Qty,Limit Price,Stop Price,Fill Price,Status,Commission,Leverage,Margin,Placing Time,Closing Time,Order ID
    CME_MINI:MNQ1!,Buy,Market,3,,,21000.00,Filled,0,,,2024-12-05 14:30:00,2024-12-05 14:30:01,1
    CME_MINI:MNQ1!,Sell,Limit,2,21010.00,,21010.00,Filled,0,,,2024-12-05 14:30:02,2024-12-05 14:35:00,2
    CME_MINI:MNQ1!,Sell,Stop,1,,20990.00,,Cancelled,0,,,2024-12-05 14:30:02,2024-12-05 14:36:00,3
    CME_MINI:MNQ1!,Sell,Limit,1,21020.00,,21020.00,Filled,0,,,2024-12-05 14:30:02,2024-12-05 14:40:00,4
    """

    // MARK: - Helpers

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// Parseert de fixture, controleert de auto-detectie en extraheert.
    private func run(_ csv: String, expectPreset presetID: String, timeZone: String = "UTC") throws -> CSVImportService.ExtractionResult {
        let table = try CSVParser.parse(csv)
        let preset = try XCTUnwrap(CSVImportPresets.detect(headers: table.headers))
        XCTAssertEqual(preset.id, presetID)
        let mapping = preset.mapping(for: table.headers, timeZoneIdentifier: timeZone)
        XCTAssertEqual(mapping.validationErrors, [])
        return service.extract(from: table, mapping: mapping, knownSymbols: known)
    }

    // MARK: - Presets

    func test_tradovatePerformance() throws {
        let result = try run(Self.tradovatePerformance, expectPreset: "tradovate_performance", timeZone: "America/New_York")
        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.trades.count, 2)

        let long = result.trades[0]
        XCTAssertEqual(long.symbol, "MNQ")
        XCTAssertEqual(long.direction, .long)
        XCTAssertEqual(long.quantity, 2)
        XCTAssertEqual(long.entryPrice, 21_000.25)
        XCTAssertEqual(long.exitPrice, 21_010.75)
        XCTAssertEqual(long.entryDate, utcDate(2024, 12, 5, 14, 31, 22))
        XCTAssertEqual(long.reportedPnL, 42)

        // Eerst verkocht, later gekocht → short.
        let short = result.trades[1]
        XCTAssertEqual(short.direction, .short)
        XCTAssertEqual(short.entryPrice, 21_020)
        XCTAssertEqual(short.exitPrice, 21_030)
        XCTAssertEqual(short.entryDate, utcDate(2024, 12, 5, 15, 0))
        XCTAssertEqual(short.reportedPnL, -20)
    }

    func test_tradovateOrders_mergesFillsAndSkipsCancelled() throws {
        let result = try run(Self.tradovateOrders, expectPreset: "tradovate_orders")
        XCTAssertEqual(result.skippedRowCount, 1)
        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.trades.count, 1)
        let trade = result.trades[0]
        XCTAssertEqual(trade.symbol, "NQ")
        XCTAssertEqual(trade.direction, .long)
        XCTAssertEqual(trade.entryPrice, 21_000)
        XCTAssertEqual(trade.exitPrice, 21_005.5)
        XCTAssertEqual(trade.fills.count, 2)
    }

    func test_ninjaTraderTrades() throws {
        let result = try run(Self.ninjaTraderTrades, expectPreset: "ninjatrader_trades")
        XCTAssertEqual(result.trades.count, 1)
        let trade = result.trades[0]
        XCTAssertEqual(trade.symbol, "ES")
        XCTAssertEqual(trade.direction, .short)
        XCTAssertEqual(trade.quantity, 2)
        XCTAssertEqual(trade.commission, 4.30, accuracy: 1e-9)
        XCTAssertEqual(trade.reportedPnL, 450)
        XCTAssertEqual(trade.entryDate, utcDate(2024, 12, 5, 9, 45, 12))
        XCTAssertEqual(trade.exitDate, utcDate(2024, 12, 5, 10, 1, 3))
    }

    func test_ninjaTraderExecutions() throws {
        let result = try run(Self.ninjaTraderExecutions, expectPreset: "ninjatrader_executions")
        XCTAssertEqual(result.trades.count, 1)
        let trade = result.trades[0]
        XCTAssertEqual(trade.symbol, "NQ")
        XCTAssertEqual(trade.exitPrice, 21_004.25)
        XCTAssertEqual(trade.commission, 4.30, accuracy: 1e-9)
    }

    func test_topstepX_usesExplicitOffset() throws {
        let result = try run(Self.topstepX, expectPreset: "topstepx", timeZone: "Europe/Amsterdam")
        XCTAssertEqual(result.trades.count, 1)
        let trade = result.trades[0]
        XCTAssertEqual(trade.symbol, "MNQ")
        XCTAssertEqual(trade.direction, .long)
        XCTAssertEqual(trade.entryDate, utcDate(2024, 12, 5, 14, 31, 22))
        XCTAssertEqual(trade.fees, 0.74, accuracy: 1e-9)
        XCTAssertEqual(trade.reportedPnL, -20)
    }

    func test_metaTrader_duplicateColumnNamesAndForexSuffix() throws {
        let result = try run(Self.metaTrader, expectPreset: "metatrader")
        XCTAssertEqual(result.trades.count, 2)

        let eur = result.trades[0]
        XCTAssertEqual(eur.symbol, "EURUSD")
        XCTAssertEqual(eur.direction, .long)
        XCTAssertEqual(eur.quantity, 0.5)
        XCTAssertEqual(eur.entryPrice, 1.0512)
        XCTAssertEqual(eur.exitPrice, 1.0522)
        XCTAssertEqual(eur.stopLoss, 1.0502)
        XCTAssertEqual(eur.takeProfit, 1.0532)
        XCTAssertEqual(eur.commission, 3.5, accuracy: 1e-9)
        XCTAssertEqual(eur.exitDate, utcDate(2024, 12, 5, 15, 2, 10))

        let gbp = result.trades[1]
        XCTAssertEqual(gbp.symbol, "GBPUSD")
        XCTAssertEqual(gbp.direction, .short)
        XCTAssertNil(gbp.stopLoss)
    }

    func test_tradingView_partialExitsAndCancelledOrders() throws {
        let result = try run(Self.tradingView, expectPreset: "tradingview")
        XCTAssertEqual(result.skippedRowCount, 1)
        XCTAssertEqual(result.trades.count, 1)
        let trade = result.trades[0]
        XCTAssertEqual(trade.symbol, "MNQ")
        XCTAssertEqual(trade.quantity, 3)
        XCTAssertEqual(trade.exitPrice ?? 0, (2 * 21_010 + 21_020) / 3, accuracy: 1e-9)
        XCTAssertEqual(trade.exitDate, utcDate(2024, 12, 5, 14, 40))
    }

    // MARK: - Mapping

    func test_validationErrors() {
        var fills = CSVColumnMapping(mode: .fills)
        XCTAssertEqual(fills.validationErrors.count, 4)
        fills.columns = [.symbol: 0, .quantity: 1, .price: 2, .time: 3]
        XCTAssertEqual(fills.validationErrors, [])

        var trades = CSVColumnMapping(mode: .trades, columns: [.symbol: 0])
        XCTAssertEqual(trades.validationErrors.count, 1)
        trades.columns[.entryTime] = 1
        trades.columns[.entryPrice] = 2
        XCTAssertEqual(trades.validationErrors, [])
    }

    func test_columnIndex_nthOccurrence() {
        let headers = ["Time", "Symbol", "Time"]
        XCTAssertEqual(CSVImportPreset.columnIndex(of: "time", in: headers), 0)
        XCTAssertEqual(CSVImportPreset.columnIndex(of: "Time#2", in: headers), 2)
        XCTAssertNil(CSVImportPreset.columnIndex(of: "Time#3", in: headers))
    }

    func test_customMapping_signedQuantityWithoutSideColumn() throws {
        let table = try CSVParser.parse("sym;qty;px;ts\nNQ;2;100;2024-12-05 10:00\nNQ;-2;101,5;2024-12-05 10:05\n")
        let mapping = CSVColumnMapping(mode: .fills, columns: [.symbol: 0, .quantity: 1, .price: 2, .time: 3], timeZoneIdentifier: "UTC")
        let result = service.extract(from: table, mapping: mapping, knownSymbols: known)
        XCTAssertEqual(result.trades.count, 1)
        XCTAssertEqual(result.trades[0].direction, .long)
        XCTAssertEqual(result.trades[0].exitPrice, 101.5)
    }

    func test_extract_reportsRowIssues() throws {
        let table = try CSVParser.parse("symbol,entry_time,entry_price\nNQ,geen datum,100\n,2024-12-05 10:00,100\nNQ,2024-12-05 10:00,100\n")
        let mapping = CSVColumnMapping(mode: .trades, columns: [.symbol: 0, .entryTime: 1, .entryPrice: 2], timeZoneIdentifier: "UTC")
        let result = service.extract(from: table, mapping: mapping, knownSymbols: known)
        XCTAssertEqual(result.issues.map(\.row), [1, 2])
        XCTAssertEqual(result.trades.count, 1)
        XCTAssertTrue(result.trades[0].isOpen)
    }

    // MARK: - Duplicaten

    func test_preview_detectsExistingAndInFileDuplicates() throws {
        let result = try run(Self.tradovatePerformance, expectPreset: "tradovate_performance", timeZone: "America/New_York")
        let first = result.trades[0]

        let existing = Trade(
            symbol: "MNQ", direction: .long, entryDate: first.entryDate,
            entryPrice: first.entryPrice, quantity: first.quantity
        )
        context.insert(existing)

        var trades = result.trades
        trades.append(result.trades[1])   // tweede keer in hetzelfde bestand

        let preview = service.preview(trades, existingTrades: [existing], knownSymbols: known)
        XCTAssertEqual(preview.map(\.isDuplicate), [true, false, true])
        XCTAssertTrue(preview.allSatisfy(\.hasKnownInstrument))
    }

    // MARK: - Opslaan

    func test_commit_fills_createsExecutionsAndCorrectPnL() throws {
        let account = Account(name: "Paper", type: .demo, startingBalance: 50_000)
        context.insert(account)

        let result = try run(Self.tradingView, expectPreset: "tradingview")
        let preview = service.preview(result.trades, existingTrades: [], knownSymbols: known)
        let created = service.commit(preview, includeDuplicates: false, account: account, instruments: [], in: context)

        XCTAssertEqual(created.count, 1)
        let trade = created[0]
        XCTAssertEqual(trade.account?.id, account.id)
        XCTAssertEqual(trade.executions.count, 3) // 1 entry + 2 exits; de geannuleerde order telt niet
        XCTAssertEqual(trade.tickSize, 0.25)
        XCTAssertEqual(trade.tickValue, 0.50)
        XCTAssertEqual(trade.session, .nyAM)

        // MNQ = $2/punt: 2 × 10 punten + 1 × 20 punten = 40 punten = $80.
        let metrics = StatsService().metrics(for: trade)
        XCTAssertEqual(metrics.netPnL, 80, accuracy: 1e-9)
        XCTAssertEqual(metrics.outcome, .win)
    }

    func test_commit_roundTrips_matchReportedPnL_andSkipDuplicates() throws {
        let result = try run(Self.tradovatePerformance, expectPreset: "tradovate_performance", timeZone: "America/New_York")
        let preview = service.preview(result.trades, existingTrades: [], knownSymbols: known)
        let created = service.commit(preview, includeDuplicates: false, account: nil, instruments: [], in: context)
        XCTAssertEqual(created.count, 2)

        let stats = StatsService()
        for (trade, imported) in zip(created, result.trades) {
            XCTAssertEqual(stats.metrics(for: trade).grossPnL, imported.reportedPnL ?? .nan, accuracy: 1e-9)
        }

        // Tweede import van hetzelfde bestand: alles is duplicaat.
        let existing = try context.fetch(FetchDescriptor<Trade>())
        let second = service.preview(result.trades, existingTrades: existing, knownSymbols: known)
        XCTAssertTrue(second.allSatisfy(\.isDuplicate))
        XCTAssertEqual(service.commit(second, includeDuplicates: false, account: nil, instruments: [], in: context).count, 0)
    }

    func test_tickSpec_unknownInstrumentDerivesPointValueFromPnL() {
        let trade = ImportedTrade(symbol: "AAPL", direction: .long, quantity: 10, entryDate: Date(),
                                  exitDate: Date(), entryPrice: 100, exitPrice: 105, reportedPnL: 100)
        let spec = CSVImportService.tickSpec(for: trade, instrument: nil)
        XCTAssertEqual(spec.tickSize, 0.01)
        XCTAssertEqual(spec.tickValue, 0.02, accuracy: 1e-12)   // puntwaarde 2

        var withoutPnL = trade
        withoutPnL.reportedPnL = nil
        let fallback = CSVImportService.tickSpec(for: withoutPnL, instrument: nil)
        XCTAssertEqual(fallback.tickValue / fallback.tickSize, 1, accuracy: 1e-12)
    }
}
