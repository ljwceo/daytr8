import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class BackupServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var directory: URL!
    private let service = BackupService()

    /// Nep-JPEG (alleen de magic bytes zijn relevant voor de extensie).
    private let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: UInt8(7), count: 64))
    private let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: UInt8(3), count: 32))

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        container = nil
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - Fixture

    private struct Fixture {
        let trade: Trade
        let account: Account
        let playbook: Playbook
        let journal: DailyJournal
    }

    @discardableResult
    private func makeFixture() throws -> Fixture {
        let account = Account(name: "Topstep 50k", type: .propFirm, startingBalance: 50_000, broker: "Topstep", dailyLossLimit: 1_000)
        let instrument = Instrument(name: "E-mini Nasdaq-100", symbol: "NQ", category: .future, tickSize: 0.25, tickValue: 5)
        let ifvg = Confluence(name: "IFVG", category: .pdArrays)
        let sweep = Confluence(name: "Sweep PDL", category: .liquidity, isActive: false)
        let tag = Tag(name: "A+ setup")
        let mistake = Mistake(name: "Te vroeg")
        let playbook = Playbook(name: "Silver Bullet")
        context.insert(account)
        context.insert(instrument)
        context.insert(ifvg)
        context.insert(sweep)
        context.insert(tag)
        context.insert(mistake)
        context.insert(playbook)

        let rule1 = PlaybookRule(text: "Wacht op sweep", sortOrder: 0)
        let rule2 = PlaybookRule(text: "Entry in FVG", sortOrder: 1)
        context.insert(rule1)
        context.insert(rule2)
        playbook.rules = [rule1, rule2]
        playbook.defaultConfluences = [ifvg]

        let trade = Trade(
            symbol: "NQ", direction: .long,
            entryDate: Date(timeIntervalSince1970: 1_733_409_000.123),
            exitDate: Date(timeIntervalSince1970: 1_733_409_600),
            entryPrice: 21_000, exitPrice: 21_020, quantity: 2,
            stopLoss: 20_990, takeProfit: 21_040, plannedRisk: 400, mae: 4, mfe: 25,
            tickSize: 0.25, tickValue: 5,
            emotionBefore: "Rustig", emotionAfter: "Tevreden", rating: 5, notes: "Top trade",
            session: .nyAM, account: account, instrument: instrument, playbook: playbook
        )
        context.insert(trade)
        trade.confluences = [ifvg, sweep]
        trade.tags = [tag]
        trade.mistakes = [mistake]

        let e1 = TradeExecution(date: trade.entryDate, price: 21_000, signedQuantity: 2, commission: 1)
        let e2 = TradeExecution(date: trade.exitDate!, price: 21_020, signedQuantity: -2, commission: 1, note: "TP")
        context.insert(e1)
        context.insert(e2)
        trade.executions = [e1, e2]

        let a1 = PlaybookRuleAdherence(followed: true)
        let a2 = PlaybookRuleAdherence(followed: false)
        context.insert(a1)
        context.insert(a2)
        a1.rule = rule1
        a2.rule = rule2
        trade.ruleAdherence = [a1, a2]

        let s1 = TradeScreenshot(imageData: jpegData, caption: "15m", sortOrder: 0)
        let s2 = TradeScreenshot(imageData: pngData, caption: "1H", sortOrder: 1)
        context.insert(s1)
        context.insert(s2)
        trade.screenshots = [s1, s2]

        let journal = DailyJournal(date: Date(timeIntervalSince1970: 1_733_356_800), preMarketPlan: "Long bias", mood: "Scherp", dayRating: 8)
        context.insert(journal)
        let js = DailyJournalScreenshot(imageData: jpegData, caption: "News")
        context.insert(js)
        journal.screenshots = [js]

        try context.save()
        return Fixture(trade: trade, account: account, playbook: playbook, journal: journal)
    }

    // MARK: - Tests

    func test_export_writesPayloadAndImages() throws {
        try makeFixture()
        let url = try service.exportBackup(from: context, to: directory)
        let reader = try ZipReader(url: url)

        XCTAssertTrue(reader.contains(BackupService.payloadPath))
        let images = reader.paths.filter { $0.hasPrefix(BackupService.imagesFolder) }
        XCTAssertEqual(images.count, 3)
        XCTAssertEqual(images.filter { $0.hasSuffix(".jpg") }.count, 2)
        XCTAssertEqual(images.filter { $0.hasSuffix(".png") }.count, 1)
    }

    func test_loadBackup_summary() throws {
        try makeFixture()
        let url = try service.exportBackup(from: context, to: directory)
        let loaded = try service.loadBackup(at: url)
        XCTAssertEqual(loaded.summary.formatVersion, BackupPayload.currentFormatVersion)
        XCTAssertEqual(loaded.summary.tradeCount, 1)
        XCTAssertEqual(loaded.summary.accountCount, 1)
        XCTAssertEqual(loaded.summary.journalCount, 1)
        XCTAssertEqual(loaded.summary.playbookCount, 1)
        XCTAssertEqual(loaded.summary.screenshotCount, 3)
    }

    func test_roundTrip_restoresEverythingAndReplacesExistingData() throws {
        let fixture = try makeFixture()
        let tradeID = fixture.trade.id
        let originalMetrics = StatsService().metrics(for: fixture.trade)
        let url = try service.exportBackup(from: context, to: directory)

        // Data die ná de backup is toegevoegd moet na de restore weg zijn.
        context.insert(Trade(symbol: "ES", direction: .short, entryDate: Date(), entryPrice: 6_000, quantity: 1))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Trade>()), 2)

        let loaded = try service.loadBackup(at: url)
        try service.restore(loaded, into: context)

        let trades = try context.fetch(FetchDescriptor<Trade>())
        XCTAssertEqual(trades.count, 1)
        let trade = try XCTUnwrap(trades.first)
        XCTAssertEqual(trade.id, tradeID)
        XCTAssertEqual(trade.entryDate.timeIntervalSince1970, 1_733_409_000.123, accuracy: 0.001)
        XCTAssertEqual(trade.stopLoss, 20_990)
        XCTAssertEqual(trade.plannedRisk, 400)
        XCTAssertEqual(trade.mfe, 25)
        XCTAssertEqual(trade.session, .nyAM)
        XCTAssertEqual(trade.rating, 5)
        XCTAssertEqual(trade.notes, "Top trade")

        XCTAssertEqual(trade.account?.name, "Topstep 50k")
        XCTAssertEqual(trade.account?.type, .propFirm)
        XCTAssertEqual(trade.account?.dailyLossLimit, 1_000)
        XCTAssertEqual(trade.instrument?.symbol, "NQ")
        XCTAssertEqual(trade.playbook?.name, "Silver Bullet")
        XCTAssertEqual(Set(trade.confluences.map(\.name)), ["IFVG", "Sweep PDL"])
        XCTAssertEqual(trade.confluences.first { $0.name == "Sweep PDL" }?.isActive, false)
        XCTAssertEqual(trade.tags.map(\.name), ["A+ setup"])
        XCTAssertEqual(trade.mistakes.map(\.name), ["Te vroeg"])

        XCTAssertEqual(trade.executions.count, 2)
        XCTAssertEqual(trade.executions.first { $0.note == "TP" }?.signedQuantity, -2)

        let adherence = Dictionary(uniqueKeysWithValues: trade.ruleAdherence.compactMap { item in
            item.rule.map { ($0.text, item.followed) }
        })
        XCTAssertEqual(adherence, ["Wacht op sweep": true, "Entry in FVG": false])

        let screenshots = trade.screenshots.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(screenshots.map(\.caption), ["15m", "1H"])
        XCTAssertEqual(screenshots.map(\.imageData), [jpegData, pngData])

        let playbook = try XCTUnwrap(try context.fetch(FetchDescriptor<Playbook>()).first)
        XCTAssertEqual(playbook.rules.sorted { $0.sortOrder < $1.sortOrder }.map(\.text), ["Wacht op sweep", "Entry in FVG"])
        XCTAssertEqual(playbook.defaultConfluences.map(\.name), ["IFVG"])

        let journal = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyJournal>()).first)
        XCTAssertEqual(journal.preMarketPlan, "Long bias")
        XCTAssertEqual(journal.dayRating, 8)
        XCTAssertEqual(journal.screenshots.map(\.imageData), [jpegData])

        // P&L blijft identiek na restore.
        XCTAssertEqual(StatsService().metrics(for: trade), originalMetrics)
    }

    func test_loadBackup_rejectsNewerFormatVersion() throws {
        try makeFixture()
        let url = try service.exportBackup(from: context, to: directory)
        var payload = try BackupService.decoder.decode(
            BackupPayload.self,
            from: try ZipReader(url: url).data(for: BackupService.payloadPath)
        )
        payload.formatVersion = BackupPayload.currentFormatVersion + 1

        let newer = directory.appendingPathComponent("newer.zip")
        let writer = try ZipWriter(url: newer)
        try writer.addFile(path: BackupService.payloadPath, data: try BackupService.encoder.encode(payload))
        try writer.finish()

        XCTAssertThrowsError(try service.loadBackup(at: newer)) { error in
            XCTAssertEqual(error as? BackupService.BackupError, .unsupportedVersion(BackupPayload.currentFormatVersion + 1))
        }
        // De bestaande data is niet aangeraakt.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Trade>()), 1)
    }

    func test_loadBackup_rejectsZipWithoutPayload() throws {
        let url = directory.appendingPathComponent("other.zip")
        let writer = try ZipWriter(url: url)
        try writer.addFile(path: "iets.txt", data: Data("hoi".utf8))
        try writer.finish()

        XCTAssertThrowsError(try service.loadBackup(at: url)) { error in
            XCTAssertEqual(error as? BackupService.BackupError, .missingPayload)
        }
    }

    func test_restore_skipsMissingImages() throws {
        try makeFixture()
        let url = try service.exportBackup(from: context, to: directory)
        let original = try ZipReader(url: url)

        // Herschrijf de backup zonder de afbeeldingen.
        let stripped = directory.appendingPathComponent("stripped.zip")
        let writer = try ZipWriter(url: stripped)
        try writer.addFile(path: BackupService.payloadPath, data: try original.data(for: BackupService.payloadPath))
        try writer.finish()

        try service.restore(try service.loadBackup(at: stripped), into: context)
        let trade = try XCTUnwrap(try context.fetch(FetchDescriptor<Trade>()).first)
        XCTAssertTrue(trade.screenshots.isEmpty)
        XCTAssertEqual(trade.executions.count, 2)
    }

    func test_fileExtension() {
        XCTAssertEqual(BackupService.fileExtension(for: jpegData), "jpg")
        XCTAssertEqual(BackupService.fileExtension(for: pngData), "png")
        XCTAssertEqual(BackupService.fileExtension(for: Data([1, 2, 3])), "bin")
    }
}
