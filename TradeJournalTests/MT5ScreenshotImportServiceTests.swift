import XCTest
import SwiftData
@testable import TradeJournal

/// Samenvoegen over screenshots, duplicaten (ook tegen het journal),
/// controles, opslaan, de markering "snel toegevoegd" en het viewmodel.
@MainActor
final class MT5ScreenshotImportServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let service = MT5ScreenshotImportService()
    private let utc = TimeZone(identifier: "UTC")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func parsed(
        _ symbol: String? = "NAS100", _ direction: TradeDirection? = .long, volume: Double? = 10,
        entry: Double? = 27173.35, exit: Double? = 27160.55, close: Date?, pnl: Double? = -109.35,
        uncertain: Set<MT5ParsedTrade.Field> = [], truncated: Bool = false
    ) -> MT5ParsedTrade {
        MT5ParsedTrade(symbol: symbol, direction: direction, volume: volume, entryPrice: entry, exitPrice: exit,
                       closeTime: close, pnl: pnl, uncertainFields: uncertain, isTruncated: truncated)
    }

    private var context0: MT5ScreenshotImportService.ValidationContext {
        MT5ScreenshotImportService.makeContext(existingTrades: [], instruments: [], now: now)
    }

    // MARK: - Samenvoegen

    func test_prepare_mergesOverlappingScreenshots_andDropsTruncatedFragments() {
        let a = parsed(close: date(4, 24, 17, 58, 32))
        let b = parsed(entry: 27175.10, exit: 27296.95, close: date(4, 24, 18, 45, 6), pnl: 1040.25)
        let c = parsed(entry: 27367.60, exit: 27351.65, close: date(4, 27, 15, 6, 35), pnl: 135.78)
        // Screenshot 1: a, b en de kop van c (afgekapt).
        let cHeaderOnly = parsed(entry: nil, exit: nil, close: nil, pnl: 135.78, truncated: true)
        // Screenshot 2: de prijsregel van b (afgekapt), c en d.
        let bDetailOnly = parsed(nil, nil, volume: nil, entry: 27175.10, exit: 27296.95, close: date(4, 24, 18, 45, 6), pnl: nil, truncated: true)
        let d = parsed(entry: 27045.81, exit: 27014.17, close: date(4, 28, 16, 30, 5), pnl: -541.01)

        let result = service.prepare([[a, b, cHeaderOnly], [bDetailOnly, c, d]], context: context0)
        XCTAssertEqual(result.rows.map(\.closeTime), [a.closeTime, b.closeTime, c.closeTime, d.closeTime])
        XCTAssertEqual(result.merged, 2, "kop van c en prijsregel van b vallen weg")
        XCTAssertEqual(result.rows.map(\.screenshotIndex), [0, 0, 1, 1])
    }

    func test_prepare_sameTradeOnTwoScreenshots_isMergedOnce() {
        let a = parsed(close: date(4, 24, 17, 58, 32), uncertain: [.pnl])
        let aAgain = parsed(close: date(4, 24, 17, 58, 32))
        let result = service.prepare([[a], [aAgain]], context: context0)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.merged, 1)
        XCTAssertTrue(result.rows[0].uncertainFields.isEmpty, "op de tweede screenshot wel zeker gelezen")
    }

    func test_prepare_conflictingReadings_areNotMerged() {
        let a = parsed(close: date(4, 24, 17, 58, 32), pnl: -109.35)
        let b = parsed(close: date(4, 24, 17, 58, 32), pnl: -1093.5)
        let result = service.prepare([[a], [b]], context: context0)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertTrue(result.rows[1].issues.contains { $0.kind == .duplicateInBatch })
    }

    func test_unmatchedTruncatedRow_isKept_unselected_withError() {
        let fragment = parsed(entry: nil, exit: nil, close: nil, pnl: 50, truncated: true)
        let result = service.prepare([[fragment]], context: context0)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertFalse(result.rows[0].isSelected)
        XCTAssertTrue(result.rows[0].hasErrors)
        XCTAssertTrue(result.rows[0].issues.contains { $0.kind == .truncated })
    }

    // MARK: - Duplicaten tegen het journal

    func test_duplicateOfExistingTrade_isDetectedAndNotSelected() {
        let close = date(4, 24, 17, 58, 32)
        let existing = Trade(symbol: "NAS100", direction: .long, entryDate: close, exitDate: close, entryPrice: 27173.35,
                             exitPrice: 27160.55, quantity: 10, manualNetPnL: -109.35)
        context.insert(existing)
        let validation = MT5ScreenshotImportService.makeContext(existingTrades: [existing], instruments: [], now: now)
        let result = service.prepare([[parsed(close: close), parsed(entry: 27175.10, exit: 27296.95, close: date(4, 24, 18), pnl: 1040.25)]], context: validation)
        XCTAssertTrue(result.rows[0].isDuplicateOfExisting)
        XCTAssertFalse(result.rows[0].isSelected)
        XCTAssertFalse(result.rows[1].isDuplicateOfExisting)
        XCTAssertTrue(result.rows[1].isSelected, "bekend symbool uit het journal, verder geen melding")
    }

    // MARK: - Controles

    func test_validation_flagsPnLNotMatchingMove_unknownSymbolAndFutureDate() {
        let known = MT5ScreenshotImportService.ValidationContext(knownSymbols: ["XAUUSD", "EURUSD"], now: now)
        let rows = service.prepare([[
            // XAUUSD: 5 punten × 1 lot × 100 = 500 → klopt.
            parsed("XAUUSD", .long, volume: 1, entry: 2345.10, exit: 2350.10, close: date(5, 1, 10), pnl: 500),
            // Zelfde beweging maar P&L 50 → past niet.
            parsed("XAUUSD", .long, volume: 1, entry: 2345.10, exit: 2350.10, close: date(5, 1, 11), pnl: 50),
            // Richting/P&L tegenstrijdig: koers ging omhoog bij een sell, toch winst.
            parsed("EURUSD", .short, volume: 0.5, entry: 1.08500, exit: 1.08600, close: date(5, 1, 12), pnl: 46),
            // EURUSD in EUR-account: 0.001 × 0.5 × 100.000 = 50 USD ≈ 46 EUR → klopt.
            parsed("EURUSD", .long, volume: 0.5, entry: 1.08500, exit: 1.08600, close: date(5, 1, 13), pnl: 46),
            // Onbekend symbool.
            parsed("GER40", .long, volume: 1, entry: 18000, exit: 18010, close: date(5, 1, 14), pnl: 10),
            // Sluittijd in de toekomst.
            parsed("EURUSD", .long, volume: 0.5, entry: 1.08500, exit: 1.08600, close: now.addingTimeInterval(86_400), pnl: 46)
        ]], context: known).rows

        func kinds(_ index: Int) -> [MT5ImportIssue.Kind] { rows[index].issues.map(\.kind) }
        XCTAssertEqual(kinds(0), [])
        XCTAssertTrue(rows[0].isSelected)
        XCTAssertEqual(kinds(1), [.pnlMismatch])
        XCTAssertFalse(rows[1].isSelected, "bij twijfel niet aangevinkt")
        XCTAssertEqual(kinds(2), [.pnlMismatch])
        XCTAssertEqual(kinds(3), [])
        XCTAssertEqual(kinds(4), [.unknownSymbol])
        XCTAssertTrue(rows[4].isSelected, "alleen onbekend symbool: wel aangevinkt, wel gemarkeerd")
        XCTAssertEqual(kinds(5), [.futureDate])
        XCTAssertFalse(rows[5].isSelected)
    }

    func test_validation_batchConsistency_flagsOutlier() {
        // NAS100 (geen preset): onderling vergelijken, ≈ 0,854 per punt·lot.
        let rows = service.prepare([[
            parsed(entry: 27173.35, exit: 27160.55, close: date(4, 24, 17), pnl: -109.35),
            parsed(entry: 27175.10, exit: 27296.95, close: date(4, 24, 18), pnl: 1040.25),
            parsed(entry: 27026.81, exit: 27114.17, close: date(4, 28, 16), pnl: 746.43),
            parsed(entry: 27113.76, exit: 27173.21, close: date(4, 29, 17), pnl: 5084.60)   // 10× te groot
        ]], context: MT5ScreenshotImportService.ValidationContext(knownSymbols: ["NAS100"], now: now)).rows
        XCTAssertEqual(rows.map { $0.issues.map(\.kind) }, [[], [], [], [.pnlMismatch]])
    }

    func test_validation_lowConfidence_untilEditedOrConfirmed() {
        var rows = service.prepare([[parsed(close: date(4, 24, 17), uncertain: [.pnl, .volume])]],
                                   context: MT5ScreenshotImportService.ValidationContext(knownSymbols: ["NAS100"], now: now)).rows
        XCTAssertEqual(rows[0].issues.map(\.kind), [.lowConfidence, .lowConfidence])
        XCTAssertFalse(rows[0].isSelected)

        rows[0].confirmedFields = [.volume]
        rows[0].editedFields = [.pnl]
        rows = service.validate(rows, context: MT5ScreenshotImportService.ValidationContext(knownSymbols: ["NAS100"], now: now))
        XCTAssertTrue(rows[0].issues.isEmpty)
    }

    func test_validation_missingFieldIsError() {
        let rows = service.prepare([[parsed(volume: nil, close: date(4, 24, 17))]], context: context0).rows
        XCTAssertTrue(rows[0].hasErrors)
        XCTAssertEqual(rows[0].issues(for: .volume).first?.kind, .missing)
    }

    // MARK: - Opslaan

    func test_commit_createsMarkedTradesWithScreenshotAccountPlaybookAndTag() throws {
        let account = Account(name: "FTMO", type: .propFirm, startingBalance: 100_000, currency: "EUR")
        let playbook = Playbook(name: "London sweep")
        let tag = Tag(name: "MT5")
        context.insert(account)
        context.insert(playbook)
        context.insert(tag)
        let close = date(4, 24, 17, 58, 32)
        var rows = service.prepare([[parsed(close: close)], [parsed("XAUUSD", .short, volume: 0.05, entry: 2345.67, exit: 2350.10, close: date(4, 25, 11), pnl: -22.15)]],
                                   context: MT5ScreenshotImportService.ValidationContext(knownSymbols: ["NAS100", "XAUUSD"], now: now)).rows
        for index in rows.indices {
            rows[index].accountID = account.id
            rows[index].playbookID = playbook.id
            rows[index].tagID = tag.id
        }
        rows[1].editedFields = [.pnl]
        let screenshots = [Data([0xFF, 0xD8, 0xFF, 1]), Data([0xFF, 0xD8, 0xFF, 2])]

        let summary = service.commit(rows, merged: 3, screenshots: screenshots, accounts: [account], playbooks: [playbook], tags: [tag],
                                     instruments: [], in: context, now: now)
        XCTAssertEqual(summary, MT5ImportSummary(imported: 2, skippedExisting: 0, mergedOnScreenshots: 3, corrected: 1, notSelected: 0))
        XCTAssertEqual(summary.skippedAsDuplicate, 3)

        let trades = try context.fetch(FetchDescriptor<Trade>(sortBy: [SortDescriptor(\.entryDate)]))
        XCTAssertEqual(trades.count, 2)
        let nas = trades[0]
        XCTAssertEqual(nas.symbol, "NAS100")
        XCTAssertEqual(nas.direction, .long)
        XCTAssertEqual(nas.quantity, 10)
        XCTAssertEqual(nas.entryPrice, 27173.35)
        XCTAssertEqual(nas.exitPrice, 27160.55)
        XCTAssertEqual(nas.exitDate, close)
        XCTAssertEqual(nas.manualNetPnL, -109.35)
        XCTAssertEqual(StatsService().metrics(for: nas).netPnL, -109.35, accuracy: 0.001)
        XCTAssertEqual(nas.account?.id, account.id)
        XCTAssertEqual(nas.playbook?.id, playbook.id)
        XCTAssertEqual(nas.tags.map(\.name), ["MT5"])
        XCTAssertTrue(nas.confluences.isEmpty)
        XCTAssertEqual(nas.screenshots.first?.imageData, screenshots[0])
        XCTAssertEqual(trades[1].screenshots.first?.imageData, screenshots[1])
        XCTAssertEqual(trades[1].direction, .short)

        let marks = try context.fetch(FetchDescriptor<TradeImportMark>())
        XCTAssertEqual(Set(marks.map(\.tradeID)), Set(trades.map(\.id)))
        XCTAssertTrue(marks.allSatisfy { $0.source == .mt5Screenshot })
    }

    func test_commit_skipsUnselectedErrorsAndDuplicates() throws {
        let close = date(4, 24, 17, 58, 32)
        let existing = Trade(symbol: "NAS100", direction: .long, entryDate: close, exitDate: close, entryPrice: 27173.35, exitPrice: 27160.55, quantity: 10)
        context.insert(existing)
        let validation = MT5ScreenshotImportService.makeContext(existingTrades: [existing], instruments: [], now: now)
        var rows = service.prepare([[
            parsed(close: close),                                              // duplicaat
            parsed(volume: nil, close: date(4, 25, 10)),                        // fout
            parsed(entry: 27000, exit: 27010, close: date(4, 26, 10), pnl: 85.40) // ok
        ]], context: validation).rows
        rows[1].isSelected = true   // ook geforceerd: een fout gaat nooit mee
        let summary = service.commit(rows, merged: 0, screenshots: [], accounts: [], playbooks: [], tags: [], instruments: [], in: context, now: now)
        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.skippedExisting, 1)
        XCTAssertEqual(summary.notSelected, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Trade>()), 2)
    }

    // MARK: - Markering

    func test_deletingTrade_removesMark_andRemoveMarkWorks() throws {
        let editing = TradeEditingService()
        let a = Trade(symbol: "NAS100", direction: .long, entryDate: now, entryPrice: 1, quantity: 1)
        let b = Trade(symbol: "NAS100", direction: .long, entryDate: now, entryPrice: 1, quantity: 1)
        context.insert(a)
        context.insert(b)
        context.insert(TradeImportMark(tradeID: a.id))
        context.insert(TradeImportMark(tradeID: b.id))
        try context.save()

        editing.delete(a, from: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<TradeImportMark>()).map(\.tradeID), [b.id])

        service.removeMark(from: b, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TradeImportMark>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Trade>()), 1)
    }

    func test_tradesList_quickAddedFilter() {
        let a = Trade(symbol: "NAS100", direction: .long, entryDate: now, exitDate: now, entryPrice: 1, exitPrice: 2, quantity: 1)
        let b = Trade(symbol: "ES", direction: .long, entryDate: now, exitDate: now, entryPrice: 1, exitPrice: 2, quantity: 1)
        context.insert(a)
        context.insert(b)
        let viewModel = TradesListViewModel()
        viewModel.quickFilter = .quickAdded
        XCTAssertEqual(viewModel.filteredAndSorted([a, b], quickAddedIDs: [b.id]).map(\.id), [b.id])
        XCTAssertTrue(viewModel.filteredAndSorted([a, b]).isEmpty)
    }

    func test_backupRoundTrip_keepsMarks_oldBackupWithoutMarksStillRestores() throws {
        let trade = Trade(symbol: "NAS100", direction: .long, entryDate: now, exitDate: now, entryPrice: 1, exitPrice: 2, quantity: 1)
        context.insert(trade)
        context.insert(TradeImportMark(tradeID: trade.id, importedAt: now))
        try context.save()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MT5Backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backup = BackupService(settingsDefaults: nil)
        let url = try backup.exportBackup(from: context, to: directory)
        let loaded = try backup.loadBackup(at: url)
        XCTAssertEqual(loaded.payload.tradeImportMarks?.map(\.tradeID), [trade.id])

        try backup.restore(loaded, into: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TradeImportMark>()).map(\.tradeID), [trade.id])

        var old = loaded.payload
        old.tradeImportMarks = nil
        old.dashboards = nil
        let oldURL = directory.appendingPathComponent("old.zip")
        let writer = try ZipWriter(url: oldURL)
        try writer.addFile(path: BackupService.payloadPath, data: try BackupService.encoder.encode(old))
        try writer.finish()
        try backup.restore(try backup.loadBackup(at: oldURL), into: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Trade>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TradeImportMark>()), 0)
    }

    // MARK: - Viewmodel

    func test_viewModel_recognizeEditAndImport() async throws {
        let account = Account(name: "Live", type: .live, startingBalance: 10_000)
        context.insert(account)
        let first = """
        NAS100 buy 10  -109.35
        27173.35 \u{2192} 27160.55  2026.04.24 17:58:32
        NAS100 buy 10  1 040.25
        27175.10 \u{2192} 27296.95  2026.04.24 18:45:06
        NAS100 sell 10  135.78
        """
        let second = """
        NAS100 sell 10  135.78
        27367.60 \u{2192} 27351.65  2026.04.27 15:06:35
        NAS100 buy 25  -1 044.67
        27300.24 \u{2192} 27251.24  2026.04.30 19:02:27
        """
        let recognizer = FakeRecognizer(textsByFirstByte: [1: first, 2: second])
        let viewModel = MT5ImportViewModel(recognizer: recognizer, parser: MT5HistoryParser(timeZone: utc))
        await viewModel.recognize([Data([1]), Data([2])], existingTrades: [], instruments: [], defaultAccountID: account.id, now: now)

        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.rows.count, 4)
        XCTAssertEqual(viewModel.mergedCount, 1, "afgekapte kop van de sell-trade")
        // NAS100 is geen preset en nog niet in het journal: wel aangevinkt, gemarkeerd als onbekend.
        XCTAssertEqual(viewModel.selectedCount, 4)

        let last = try XCTUnwrap(viewModel.rows.last)
        viewModel.update(last.id) { $0.pnl = -1044.76 }
        XCTAssertEqual(viewModel.rows.last?.editedFields, [.pnl])
        viewModel.toggle(viewModel.rows[0].id)
        XCTAssertEqual(viewModel.selectedCount, 3)

        viewModel.update(viewModel.rows[1].id) { $0.volume = nil }
        XCTAssertFalse(viewModel.rows[1].isSelected, "een fout haalt het vinkje weg")
        viewModel.toggle(viewModel.rows[1].id)
        XCTAssertFalse(viewModel.rows[1].isSelected, "en kan niet aangevinkt worden")

        let summary = viewModel.importSelected(accounts: [account], playbooks: [], tags: [], instruments: [], in: context, now: now)
        XCTAssertEqual(summary.imported, 2)
        XCTAssertEqual(summary.corrected, 1)
        XCTAssertEqual(summary.mergedOnScreenshots, 1)
        XCTAssertEqual(summary.notSelected, 2)
        XCTAssertEqual(viewModel.phase, .finished(summary))
        let trades = try context.fetch(FetchDescriptor<Trade>())
        XCTAssertTrue(trades.allSatisfy { $0.account?.id == account.id })
        XCTAssertTrue(trades.contains { $0.manualNetPnL == -1044.76 })
    }

    func test_viewModel_nothingRecognized_staysOnPicking() async {
        let viewModel = MT5ImportViewModel(recognizer: FakeRecognizer(textsByFirstByte: [1: "Een foto van je hond"]))
        await viewModel.recognize([Data([1])], existingTrades: [], instruments: [], defaultAccountID: nil, now: now)
        XCTAssertEqual(viewModel.phase, .picking)
        XCTAssertNotNil(viewModel.message)
    }
}

/// Nep-OCR: tekst per afbeelding (op de eerste byte), als regels zonder posities.
private struct FakeRecognizer: ScreenshotTextRecognizing {
    let textsByFirstByte: [UInt8: String]

    func recognizeLines(in imageData: Data) async throws -> [String] {
        (textsByFirstByte[imageData.first ?? 0] ?? "").components(separatedBy: "\n")
    }
}
