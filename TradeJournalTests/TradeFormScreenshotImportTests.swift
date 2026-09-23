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
