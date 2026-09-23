import XCTest
import SwiftData
@testable import TradeJournal

/// Screenshot-import in het tradeformulier (SPEC.md §12): velden invullen,
/// "uit OCR"-markeringen, alternatieven, afleiden via tick size/value en
/// foutafhandeling. De OCR zelf wordt vervangen door een nep-herkenner.
@MainActor
final class TradeFormScreenshotImportTests: XCTestCase {

    private struct StubRecognizer: ScreenshotTextRecognizing {
        var lines: [String] = []
        var error: Error?

        func recognizeLines(in imageData: Data) async throws -> [String] {
            if let error { throw error }
            return lines
        }
    }

    private let screenshot = Data([0x89, 0x50, 0x4E, 0x47])

    private func makeViewModel(recognizer: StubRecognizer = StubRecognizer()) -> TradeFormViewModel {
        TradeFormViewModel(mode: .create, textRecognizer: recognizer, screenshotTemplates: ScreenshotTemplateStore.bundledTemplates())
    }

    // MARK: - Importeren

    func test_import_fillsFieldsAndAttachesScreenshot() async {
        let lines = [
            "TopstepX",
            "Contract  /MNQ",
            "Type  Short",
            "Size  2",
            "Entry Price  21,450.25",
            "Exit Price  21,440.00",
            "PnL  $41.00",
            "Fees  $2.22"
        ]
        let viewModel = makeViewModel(recognizer: StubRecognizer(lines: lines))

        await viewModel.importScreenshot(screenshot, instruments: [])

        XCTAssertEqual(viewModel.pendingScreenshots, [screenshot], "Screenshot automatisch als bijlage")
        XCTAssertEqual(viewModel.values.symbol, "MNQ")
        XCTAssertEqual(viewModel.values.tickSize, 0.25, "Tick size uit de MNQ-preset")
        XCTAssertEqual(viewModel.values.tickValue, 0.50)
        XCTAssertEqual(viewModel.values.direction, .short)
        XCTAssertEqual(viewModel.values.quantity, 2)
        XCTAssertEqual(viewModel.values.entryPrice, 21450.25)
        XCTAssertEqual(viewModel.values.exitPrice, 21440.00)
        XCTAssertNotNil(viewModel.values.exitDate, "Met exit-prijs is de trade gesloten")
        XCTAssertEqual(viewModel.values.fees, 2.22)
        XCTAssertEqual(viewModel.entryStyle, .detailed)
        XCTAssertEqual(viewModel.ocrOrigin(for: .entryPrice), .recognized)
        XCTAssertEqual(viewModel.ocrOrigin(for: .symbol), .recognized)
        XCTAssertNil(viewModel.ocrOrigin(for: .stopLoss))
        XCTAssertEqual(viewModel.livePreview.grossPnL, 41, accuracy: 0.001, "10.25 punt × 2 × $2")
        XCTAssertTrue(viewModel.ocrMessage?.contains("TopstepX") ?? false)
        XCTAssertFalse(viewModel.isRecognizingScreenshot)
    }

    func test_import_ocrFailure_keepsFormAndAttachesScreenshot() async {
        struct OCRFailed: Error {}
        let viewModel = makeViewModel(recognizer: StubRecognizer(error: OCRFailed()))
        let symbolBefore = viewModel.values.symbol

        await viewModel.importScreenshot(screenshot, instruments: [])

        XCTAssertEqual(viewModel.pendingScreenshots.count, 1)
        XCTAssertEqual(viewModel.values.symbol, symbolBefore)
        XCTAssertTrue(viewModel.ocrOrigins.isEmpty)
        XCTAssertNotNil(viewModel.ocrMessage)
        XCTAssertFalse(viewModel.isRecognizingScreenshot)
    }

    func test_import_nothingRecognized_showsMessage() async {
        let viewModel = makeViewModel(recognizer: StubRecognizer(lines: ["Hello world", "Battery 87%"]))

        await viewModel.importScreenshot(screenshot, instruments: [])

        XCTAssertEqual(viewModel.pendingScreenshots.count, 1)
        XCTAssertTrue(viewModel.ocrOrigins.isEmpty)
        XCTAssertTrue(viewModel.ocrMessage?.contains("Geen tradegegevens") ?? false)
    }

    /// Echte MT5-screenshot (opengeklapte trade), NAS100 zonder eigen
    /// instrument: de P&L van de broker gaat vóór de berekening met de
    /// standaard tick value (die gaf 33.93 × 50 × $100 = 169.650).
    func test_import_metaTrader5_brokerPnLGoesBeforeCalculation() async throws {
        let lines = [
            "NAS100 buy 50  #119092393",
            "NAS100 Cash",
            "27371.55 \u{2192} 27405.48  1 450.14",
            "\u{0394} = 3393 (0.12%)",
            "2026.04.30 15:12:01 \u{2192} 2026.04.30 15:22:27",
            "S/L:  27406.48  Swap:  -",
            "T/P:  27441.99  Charges:  -"
        ]
        let viewModel = makeViewModel(recognizer: StubRecognizer(lines: lines))

        await viewModel.importScreenshot(screenshot, instruments: [])

        XCTAssertEqual(viewModel.entryStyle, .detailed)
        XCTAssertEqual(viewModel.values.entryPrice, 27371.55)
        XCTAssertEqual(viewModel.values.exitPrice, 27405.48)
        XCTAssertEqual(viewModel.brokerNetPnL, 1450.14)
        XCTAssertEqual(viewModel.ocrOrigin(for: .netPnL), .derived, "Bruto van de screenshot min (lege) kosten")
        XCTAssertEqual(viewModel.livePreview.netPnL, 1450.14, accuracy: 0.001)

        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let trade = viewModel.save(in: container.mainContext)

        XCTAssertEqual(trade.manualNetPnL, 1450.14)
        XCTAssertEqual(trade.entryPrice, 27371.55, "Prijzen blijven bewaard")
        XCTAssertEqual(StatsService().metrics(for: trade).netPnL, 1450.14, accuracy: 0.001)
    }

    func test_apply_brokerPnLMinusCosts_andClearingUsesPrices() {
        let viewModel = makeViewModel()
        var result = ScreenshotParseResult(templateID: "metatrader", templateName: "MetaTrader")
        result.symbol = ParsedField(value: "NAS100", source: "MetaTrader")
        result.direction = ParsedField(value: TradeDirection.long, source: "MetaTrader")
        result.entryPrice = ParsedField(value: 27371.55, source: "MetaTrader")
        result.exitPrice = ParsedField(value: 27405.48, source: "MetaTrader")
        result.quantity = ParsedField(value: 50.0, source: "MetaTrader")
        result.grossPnL = ParsedField(value: 1450.14, source: "MetaTrader")
        result.commission = ParsedField(value: 3.5, source: "MetaTrader")

        viewModel.applyScreenshotResult(result, instruments: [])

        XCTAssertEqual(viewModel.brokerNetPnL ?? 0, 1446.64, accuracy: 0.0001, "Bruto − commissie")
        XCTAssertEqual(viewModel.livePreview.grossPnL, 1450.14, accuracy: 0.001)

        viewModel.brokerNetPnL = nil
        let pointValue = viewModel.values.tickValue / viewModel.values.tickSize
        XCTAssertEqual(viewModel.livePreview.grossPnL, (27405.48 - 27371.55) * 50 * pointValue, accuracy: 0.01, "Leeg: weer uit de prijzen")
    }

    /// Lijst met meerdere trades: de bruto-alternatieven zijn kiesbaar als
    /// resultaat, net als de prijzen.
    func test_candidates_brokerPnLFromGrossAlternatives() {
        let viewModel = makeViewModel()
        var result = ScreenshotParseResult(templateID: "metatrader", templateName: "MetaTrader")
        result.symbol = ParsedField(value: "NAS100", source: "MetaTrader")
        result.entryPrice = ParsedField(value: 27722.47, alternatives: [27615.86], source: "MetaTrader")
        result.exitPrice = ParsedField(value: 27799.66, alternatives: [27532.41], source: "MetaTrader")
        result.grossPnL = ParsedField(value: -169.53, alternatives: [183.17], source: "MetaTrader")

        viewModel.applyScreenshotResult(result, instruments: [])

        XCTAssertEqual(viewModel.ocrCandidates(for: .netPnL).map(\.isSelected), [true, false])
        viewModel.selectOCRCandidate(1, for: .netPnL)
        XCTAssertEqual(viewModel.brokerNetPnL, 183.17)
        XCTAssertEqual(viewModel.entryStyle, .detailed)
    }

    /// Tabel met meerdere trades: de eerste wordt ingevuld, de andere zijn
    /// als hele trade te kiezen (geen mix van waarden uit verschillende rijen).
    func test_import_table_selectsWholeTrade() async {
        let lines = [
            "Tradovate",
            "Performance",
            "Symbol  Qty  Buy Price  Sell Price  P&L      Bought Timestamp     Sold Timestamp       Duration",
            "MNQZ5   2    21450.25   21462.75    $50.00   09/22/2025 09:31:22  09/22/2025 09:45:10  13min 48sec",
            "ESZ5    1    6650.50    6655.00     $225.00  09/22/2025 10:12:40  09/22/2025 10:02:05  10min 35sec",
            "MNQZ5   1    21470.00   21465.50    $(9.00)  09/22/2025 11:00:01  09/22/2025 11:03:30  3min 29sec"
        ]
        let viewModel = makeViewModel(recognizer: StubRecognizer(lines: lines))

        await viewModel.importScreenshot(screenshot, instruments: [])

        XCTAssertEqual(viewModel.values.symbol, "MNQ")
        XCTAssertEqual(viewModel.values.direction, .long)
        XCTAssertEqual(viewModel.values.entryPrice, 21450.25)
        XCTAssertEqual(viewModel.brokerNetPnL, 50)
        XCTAssertEqual(viewModel.ocrTradeCandidates.map(\.isSelected), [true, false, false])
        XCTAssertTrue(viewModel.ocrTradeCandidates[1].label.hasPrefix("ES · Short · 6655"), viewModel.ocrTradeCandidates[1].label)
        XCTAssertTrue(viewModel.ocrMessage?.contains("3 trades") ?? false)

        viewModel.selectOCRTrade(1)

        XCTAssertEqual(viewModel.values.symbol, "ES")
        XCTAssertEqual(viewModel.values.tickValue, 12.5, "Tick value uit de ES-preset")
        XCTAssertEqual(viewModel.values.direction, .short)
        XCTAssertEqual(viewModel.values.entryPrice, 6655)
        XCTAssertEqual(viewModel.values.exitPrice, 6650.5)
        XCTAssertEqual(viewModel.values.quantity, 1)
        XCTAssertEqual(viewModel.brokerNetPnL, 225)
        XCTAssertEqual(viewModel.ocrTradeCandidates.map(\.isSelected), [false, true, false])
    }

    // MARK: - Symbool tegen de instrumenttabel

    func test_apply_symbolMatchesOwnInstrument() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let custom = Instrument(name: "Eigen DAX", symbol: "FDXM", category: .future, tickSize: 1, tickValue: 5)
        container.mainContext.insert(custom)

        let viewModel = makeViewModel()
        var result = ScreenshotParseResult()
        result.symbol = ParsedField(value: "fdxm", source: "Generiek")
        viewModel.applyScreenshotResult(result, instruments: [custom])

        XCTAssertEqual(viewModel.values.symbol, "FDXM")
        XCTAssertTrue(viewModel.values.instrument === custom)
        XCTAssertEqual(viewModel.values.tickSize, 1)
        XCTAssertEqual(viewModel.values.tickValue, 5)
    }

    // MARK: - Afleiden

    func test_apply_derivesMissingExitFromPnL() {
        let viewModel = makeViewModel()
        var result = ScreenshotParseResult(templateID: "tradovate", templateName: "Tradovate")
        result.symbol = ParsedField(value: "MNQ", source: "Tradovate")
        result.direction = ParsedField(value: TradeDirection.long, source: "Tradovate")
        result.entryPrice = ParsedField(value: 21450.25, source: "Tradovate")
        result.quantity = ParsedField(value: 2.0, source: "Tradovate")
        result.grossPnL = ParsedField(value: 50.0, source: "Tradovate")

        viewModel.applyScreenshotResult(result, instruments: [])

        XCTAssertEqual(viewModel.values.exitPrice ?? 0, 21462.75, accuracy: 0.0001, "12.5 punt × 2 × $2 = $50")
        XCTAssertEqual(viewModel.ocrOrigin(for: .exitPrice), .derived)
        XCTAssertNotNil(viewModel.values.exitDate)
    }

    func test_apply_derivesQuantityAndCommission() {
        let viewModel = makeViewModel()
        var result = ScreenshotParseResult()
        result.symbol = ParsedField(value: "ES", source: "Generiek")
        result.direction = ParsedField(value: TradeDirection.short, source: "Generiek")
        result.entryPrice = ParsedField(value: 6655.00, source: "Generiek")
        result.exitPrice = ParsedField(value: 6650.50, source: "Generiek")
        result.grossPnL = ParsedField(value: 450.0, source: "Generiek")
        result.netPnL = ParsedField(value: 445.80, source: "Generiek")

        viewModel.applyScreenshotResult(result, instruments: [])

        XCTAssertEqual(viewModel.values.quantity, 2, "4.5 punt × $50 = $225 per contract")
        XCTAssertEqual(viewModel.ocrOrigin(for: .quantity), .derived)
        XCTAssertEqual(viewModel.values.commission, 4.20, accuracy: 0.0001, "Bruto − netto")
        XCTAssertEqual(viewModel.ocrOrigin(for: .commission), .derived)
    }

    func test_apply_unknownSymbol_doesNotDeriveWithGuessedTicks() {
        let viewModel = makeViewModel()
        var result = ScreenshotParseResult()
        result.symbol = ParsedField(value: "XYZ", source: "Generiek")
        result.entryPrice = ParsedField(value: 100.0, source: "Generiek")
        result.netPnL = ParsedField(value: 50.0, source: "Generiek")

        viewModel.applyScreenshotResult(result, instruments: [])

        XCTAssertNil(viewModel.values.exitPrice, "Zonder tick-specificatie geen berekende exit")
        XCTAssertNil(viewModel.ocrOrigin(for: .exitPrice))
    }

    func test_apply_onlyResult_switchesToQuickEntry() {
        let viewModel = makeViewModel()
        var result = ScreenshotParseResult()
        result.symbol = ParsedField(value: "NQ", source: "Generiek")
        result.netPnL = ParsedField(value: -120.0, source: "Generiek")

        viewModel.applyScreenshotResult(result, instruments: [])

        XCTAssertEqual(viewModel.entryStyle, .quick)
        XCTAssertFalse(viewModel.quickIsProfit)
        XCTAssertEqual(viewModel.quickAmount, 120)
        XCTAssertEqual(viewModel.ocrOrigin(for: .netPnL), .recognized)
    }

    // MARK: - Alternatieven

    func test_candidates_chipRowAndSelection() {
        let viewModel = makeViewModel()
        var result = ScreenshotParseResult()
        result.symbol = ParsedField(value: "MES", source: "Generiek")
        result.entryPrice = ParsedField(value: 6650.25, alternatives: [6651.00], source: "Generiek")

        viewModel.applyScreenshotResult(result, instruments: [])

        XCTAssertEqual(viewModel.ocrCandidates(for: .symbol), [], "Eén kandidaat: geen chip-rij")
        let chips = viewModel.ocrCandidates(for: .entryPrice)
        XCTAssertEqual(chips.count, 2)
        XCTAssertEqual(chips.map(\.isSelected), [true, false])

        viewModel.selectOCRCandidate(1, for: .entryPrice)

        XCTAssertEqual(viewModel.values.entryPrice, 6651.00)
        XCTAssertEqual(viewModel.ocrCandidates(for: .entryPrice).map(\.isSelected), [false, true])
    }

    // MARK: - StatsService

    func test_stats_exitPriceForGrossPnL() {
        let stats = StatsService()
        XCTAssertEqual(stats.exitPrice(forGrossPnL: 50, entryPrice: 21450.25, quantity: 2, direction: .long, tickSize: 0.25, tickValue: 0.5), 21462.75)
        XCTAssertEqual(stats.exitPrice(forGrossPnL: 270, entryPrice: 1.0845, quantity: 1, direction: .long, tickSize: 0.00001, tickValue: 1), 1.0872)
        XCTAssertEqual(stats.exitPrice(forGrossPnL: 225, entryPrice: 6655, quantity: 1, direction: .short, tickSize: 0.25, tickValue: 12.5), 6650.5)
        XCTAssertNil(stats.exitPrice(forGrossPnL: 50, entryPrice: 100, quantity: 0, direction: .long, tickSize: 0.25, tickValue: 5))
    }

    func test_stats_quantityForGrossPnL() {
        let stats = StatsService()
        XCTAssertEqual(stats.quantity(forGrossPnL: 405, entryPrice: 21450.25, exitPrice: 21470.5, direction: .long, tickSize: 0.25, tickValue: 5), 1)
        XCTAssertEqual(stats.quantity(forGrossPnL: 27, entryPrice: 1.0845, exitPrice: 1.0872, direction: .long, tickSize: 0.00001, tickValue: 1), 0.1)
        XCTAssertNil(stats.quantity(forGrossPnL: 50, entryPrice: 100, exitPrice: 100, direction: .long, tickSize: 0.25, tickValue: 5))
        XCTAssertNil(stats.quantity(forGrossPnL: -50, entryPrice: 100, exitPrice: 101, direction: .long, tickSize: 0.25, tickValue: 5), "Tegenstrijdig teken")
    }
}
