import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class TradeFormViewModelTests: XCTestCase {

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

    // MARK: - Validatie

    func test_isValid_falseWithoutSymbol_trueWithOnlySymbol() {
        let viewModel = TradeFormViewModel(mode: .create)
        XCTAssertFalse(viewModel.isValid)

        viewModel.values.symbol = "NQ"
        XCTAssertTrue(viewModel.isValid, "Alleen het symbool is verplicht")
    }

    // MARK: - Live preview

    func test_missingFields_onlySymbolIsRequired() {
        let viewModel = TradeFormViewModel(mode: .create)
        viewModel.values.symbol = ""
        viewModel.values.entryPrice = 0
        viewModel.values.exitPrice = nil
        XCTAssertEqual(viewModel.missingFields, ["Symbool (of kies een preset)"])

        viewModel.values.symbol = "NQ"
        XCTAssertTrue(viewModel.isValid)
        XCTAssertTrue(viewModel.hasNoPrices)
    }

    func test_missingFields_exitPriceRequiresEntryPrice() {
        let viewModel = TradeFormViewModel(mode: .create)
        viewModel.values.symbol = "NQ"
        viewModel.values.entryPrice = 0
        viewModel.values.exitPrice = 18_010
        XCTAssertFalse(viewModel.isValid)

        viewModel.values.entryPrice = 18_000
        XCTAssertTrue(viewModel.isValid)
    }

    func test_livePreview_computesNetPnLAndRMultiple() {
        let viewModel = TradeFormViewModel(mode: .create)
        viewModel.values.symbol = "NQ"
        viewModel.values.direction = .long
        viewModel.values.entryPrice = 18_000
        viewModel.values.exitDate = Date()
        viewModel.values.exitPrice = 18_010
        viewModel.values.quantity = 1
        viewModel.values.tickSize = 0.25
        viewModel.values.tickValue = 5
        viewModel.values.plannedRisk = 100

        let metrics = viewModel.livePreview

        // 10 punten / 0.25 tick = 40 ticks × $5 = $200.
        XCTAssertEqual(metrics.netPnL, 200, accuracy: 0.0001)
        XCTAssertEqual(metrics.rMultiple ?? 0, 2.0, accuracy: 0.0001)
        XCTAssertEqual(metrics.outcome, .win)
    }

    // MARK: - Instrument preset

    func test_applyInstrumentPreset_updatesTickValuesAndDefaultQuantity() {
        let instrument = Instrument(name: "E-mini Nasdaq-100", symbol: "NQ", category: .future, tickSize: 0.25, tickValue: 5.0, defaultQuantity: 3, isBuiltIn: true)
        context.insert(instrument)

        let viewModel = TradeFormViewModel(mode: .create)
        viewModel.values.quantity = 0
        viewModel.applyInstrumentPreset(instrument)

        XCTAssertEqual(viewModel.values.symbol, "NQ")
        XCTAssertEqual(viewModel.values.tickSize, 0.25)
        XCTAssertEqual(viewModel.values.tickValue, 5.0)
        XCTAssertEqual(viewModel.values.quantity, 3)
        XCTAssertEqual(viewModel.values.instrument, instrument)
    }

    // MARK: - Toggles

    func test_toggleConfluenceTagAndMistake() {
        let confluence = Confluence(name: "IFVG", category: .pdArrays)
        let tag = Tag(name: "A+")
        let mistake = Mistake(name: "Te vroeg entry")
        context.insert(confluence)
        context.insert(tag)
        context.insert(mistake)

        let viewModel = TradeFormViewModel(mode: .create)
        XCTAssertFalse(viewModel.isSelected(confluence))

        viewModel.toggle(confluence)
        XCTAssertTrue(viewModel.isSelected(confluence))
        viewModel.toggle(confluence)
        XCTAssertFalse(viewModel.isSelected(confluence))

        viewModel.toggle(tag)
        XCTAssertTrue(viewModel.isSelected(tag))

        viewModel.toggle(mistake)
        XCTAssertTrue(viewModel.isSelected(mistake))
    }

    func test_applyPlaybook_resetsFollowedRules() {
        let playbook = Playbook(name: "Silver Bullet")
        context.insert(playbook)
        let rule = PlaybookRule(text: "Sweep + IFVG")
        rule.playbook = playbook
        context.insert(rule)
        playbook.rules.append(rule)

        let viewModel = TradeFormViewModel(mode: .create)
        viewModel.applyPlaybook(playbook)
        viewModel.setRule(rule, followed: true)
        XCTAssertTrue(viewModel.isRuleFollowed(rule))

        viewModel.applyPlaybook(nil)
        XCTAssertFalse(viewModel.isRuleFollowed(rule))
    }

    // MARK: - Opslaan

    func test_save_createMode_insertsNewTradeWithPendingScreenshots() throws {
        let viewModel = TradeFormViewModel(mode: .create)
        viewModel.values.symbol = "NQ"
        viewModel.values.entryPrice = 18_000
        viewModel.addPendingScreenshot(Data([0x1]))
        viewModel.addPendingScreenshot(Data([0x2]))

        let trade = viewModel.save(in: context)

        XCTAssertEqual(trade.symbol, "NQ")
        XCTAssertEqual(trade.screenshots.count, 2)
        XCTAssertTrue(viewModel.pendingScreenshots.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Trade>()).count, 1)
    }

    func test_save_editMode_updatesExistingTrade() throws {
        let service = TradeEditingService()
        var values = TradeEditingService.FormValues()
        values.symbol = "NQ"
        values.entryPrice = 18_000
        let trade = service.createTrade(from: values, in: context)

        let viewModel = TradeFormViewModel(mode: .edit(trade))
        viewModel.values.symbol = "MNQ"
        viewModel.values.rating = 5

        let saved = viewModel.save(in: context)

        XCTAssertEqual(saved.id, trade.id)
        XCTAssertEqual(trade.symbol, "MNQ")
        XCTAssertEqual(trade.rating, 5)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Trade>()).count, 1)
    }

    // MARK: - Standaardwaarden

    func test_createMode_prefillsFromLastTrade() throws {
        let service = TradeEditingService()
        var values = TradeEditingService.FormValues()
        values.symbol = "ES"
        values.direction = .short
        values.quantity = 2
        values.entryPrice = 5_000
        let lastTrade = service.createTrade(from: values, in: context)

        let viewModel = TradeFormViewModel(mode: .create, lastTrade: lastTrade)

        XCTAssertEqual(viewModel.values.symbol, "ES")
        XCTAssertEqual(viewModel.values.direction, .short)
        XCTAssertEqual(viewModel.values.quantity, 2)
        XCTAssertEqual(viewModel.values.entryPrice, 0, "Nieuwe trade begint zonder resultaat-specifieke prijzen")
    }

    // MARK: - Snelle invoer

    func test_quickEntry_onlySymbolRequired_andSavesManualPnL() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let viewModel = TradeFormViewModel(mode: .create)
        XCTAssertEqual(viewModel.entryStyle, .detailed, "Standaard uitgebreid")

        viewModel.entryStyle = .quick
        viewModel.values.symbol = ""
        XCTAssertEqual(viewModel.missingFields, ["Symbool (of kies een preset)"])

        viewModel.values.symbol = "NQ"
        viewModel.quickIsProfit = false
        viewModel.quickAmount = 250
        XCTAssertTrue(viewModel.isValid)
        XCTAssertEqual(viewModel.livePreview.netPnL, -250, accuracy: 0.001)

        let trade = viewModel.save(in: context)
        XCTAssertEqual(trade.manualNetPnL, -250)
        XCTAssertNotNil(trade.exitDate, "Snelle trade telt als gesloten")
        let metrics = StatsService().metrics(for: trade)
        XCTAssertEqual(metrics.netPnL, -250, accuracy: 0.001)
        XCTAssertEqual(metrics.outcome, .loss)

        // Bewerken opent weer in "Snel" met hetzelfde resultaat.
        let edit = TradeFormViewModel(mode: .edit(trade))
        XCTAssertEqual(edit.entryStyle, .quick)
        XCTAssertFalse(edit.quickIsProfit)
        XCTAssertEqual(edit.quickAmount, 250)
    }

    func test_detailedEntry_clearsManualPnL() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let trade = Trade(symbol: "NQ", direction: .long, entryDate: Date(), exitDate: Date(), entryPrice: 0, quantity: 1, manualNetPnL: 100)
        context.insert(trade)

        let viewModel = TradeFormViewModel(mode: .edit(trade))
        viewModel.entryStyle = .detailed
        viewModel.values.entryPrice = 18_000
        viewModel.values.exitPrice = 18_010
        viewModel.values.tickSize = 0.25
        viewModel.values.tickValue = 5
        viewModel.save(in: context)
        XCTAssertNil(trade.manualNetPnL)
        XCTAssertEqual(StatsService().metrics(for: trade).netPnL, 200, accuracy: 0.001)
    }
}
