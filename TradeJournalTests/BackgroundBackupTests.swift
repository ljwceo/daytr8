import XCTest
import SwiftData
@testable import TradeJournal

/// Backups op de achtergrond: `BackupExportActor` (eigen `ModelContext`) en
/// `BackupCoordinator` (nooit twee automatische backups tegelijk).
@MainActor
final class BackgroundBackupTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var folder: URL!
    private var directory: URL!

    private let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
    private let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        suiteName = "BackgroundBackupTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("BackgroundBackupTests-folder-\(UUID().uuidString)")
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackgroundBackupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        try super.tearDownWithError()
    }

    private var settings: BackupSettings { BackupSettings(defaults: defaults) }

    private func autoBackups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(AutoBackupService.fileNamePrefix) }
    }

    /// Account, twee trades met screenshots en een journal met screenshot.
    private func insertFixture() throws {
        let account = Account(name: "Topstep 50K", type: .propFirm, startingBalance: 50_000)
        context.insert(account)
        for (index, symbol) in ["NQ", "ES"].enumerated() {
            let trade = Trade(symbol: symbol, direction: .long, entryDate: Date(timeIntervalSince1970: 1_733_400_000 + Double(index) * 3_600), entryPrice: 100, quantity: 1)
            context.insert(trade)
            trade.account = account
            let shot = TradeScreenshot(imageData: index == 0 ? jpegData : pngData, caption: "shot \(index)")
            context.insert(shot)
            trade.screenshots = [shot]
        }
        let journal = DailyJournal(date: Date(timeIntervalSince1970: 1_733_356_800), preMarketPlan: "Long bias")
        context.insert(journal)
        let journalShot = DailyJournalScreenshot(imageData: jpegData, caption: "News")
        context.insert(journalShot)
        journal.screenshots = [journalShot]
        try context.save()
    }

    /// Volgorde van fetches is niet gegarandeerd; vergelijk op id gesorteerd.
    private func normalized(_ payload: BackupPayload) -> BackupPayload {
        var copy = payload
        copy.accounts.sort { $0.id.uuidString < $1.id.uuidString }
        copy.trades.sort { $0.id.uuidString < $1.id.uuidString }
        copy.dailyJournals.sort { $0.id.uuidString < $1.id.uuidString }
        return copy
    }

    // MARK: - BackupExportActor

    func test_backgroundExport_matchesMainThreadExport() async throws {
        try insertFixture()
        let service = BackupService(settingsDefaults: nil)
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let mainDirectory = directory.appendingPathComponent("main")
        let backgroundDirectory = directory.appendingPathComponent("background")
        try FileManager.default.createDirectory(at: mainDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backgroundDirectory, withIntermediateDirectories: true)

        let mainURL = try service.exportBackup(from: context, to: mainDirectory, now: now)
        let actor = BackupExportActor(modelContainer: container)
        let backgroundURL = try await actor.exportBackup(service: service, to: backgroundDirectory, now: now)

        XCTAssertEqual(mainURL.lastPathComponent, backgroundURL.lastPathComponent)
        let mainBackup = try service.loadBackup(at: mainURL)
        let backgroundBackup = try service.loadBackup(at: backgroundURL)
        XCTAssertEqual(backgroundBackup.payload.formatVersion, BackupPayload.currentFormatVersion)
        XCTAssertEqual(normalized(backgroundBackup.payload), normalized(mainBackup.payload))
        XCTAssertEqual(backgroundBackup.summary, mainBackup.summary)
        XCTAssertEqual(backgroundBackup.summary.screenshotCount, 3)

        // Zelfde afbeeldingen in de zip.
        XCTAssertEqual(try ZipReader(url: backgroundURL).paths.sorted(), try ZipReader(url: mainURL).paths.sorted())

        // En terug te zetten.
        let restoreContainer = try ModelContainer(for: Schema(AppSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        try service.restore(backgroundBackup, into: restoreContainer.mainContext)
        XCTAssertEqual(try restoreContainer.mainContext.fetchCount(FetchDescriptor<Trade>()), 2)
    }

    func test_backgroundExport_seesUnsavedMainContextChanges() async throws {
        try insertFixture()
        context.insert(Trade(symbol: "CL", direction: .short, entryDate: Date(), entryPrice: 70, quantity: 1))
        // Niet opgeslagen: `exportInBackground` slaat eerst op.
        let url = try await BackupExportActor.exportInBackground(container: container, service: BackupService(settingsDefaults: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try BackupService(settingsDefaults: nil).loadBackup(at: url).summary.tradeCount, 3)
    }

    // MARK: - BackupCoordinator

    func test_coordinator_runIfDue_writesBackupAndUpdatesSettings() async throws {
        try insertFixture()
        try AutoBackupService(settings: settings).setFolder(folder)
        settings.autoBackupFrequency = .daily
        let coordinator = BackupCoordinator(settings: settings, backupService: BackupService(settingsDefaults: nil))
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let url = await coordinator.runAutoBackupIfDue(container: container, isLaunch: true, now: now)
        XCTAssertNotNil(url)
        XCTAssertEqual(try autoBackups().count, 1)
        XCTAssertEqual(settings.lastBackupDate, now)
        XCTAssertEqual(settings.lastAutoBackupDate, now)
        XCTAssertNil(settings.lastAutoBackupError)
        XCTAssertFalse(coordinator.isAutoBackupRunning)

        // Zelfde dag: niet opnieuw.
        let again = await coordinator.runAutoBackupIfDue(container: container, isLaunch: false, now: now.addingTimeInterval(60))
        XCTAssertNil(again)
        XCTAssertEqual(coordinator.startedAutoBackupCount, 1)

        // De backup in de map is geldig.
        let first = folder.appendingPathComponent(try autoBackups()[0])
        XCTAssertEqual(try BackupService().loadBackup(at: first).summary.tradeCount, 2)
    }

    func test_coordinator_concurrentRequests_produceOneBackup() async throws {
        try insertFixture()
        try AutoBackupService(settings: settings).setFolder(folder)
        settings.autoBackupFrequency = .everyLaunch
        let coordinator = BackupCoordinator(settings: settings, backupService: BackupService(settingsDefaults: nil))
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        // App-start en direct daarna `.active` (andere minuut → andere
        // bestandsnaam als er toch twee zouden lopen).
        async let launch = coordinator.runAutoBackupIfDue(container: container, isLaunch: true, now: now)
        async let foreground = coordinator.runAutoBackupIfDue(container: container, isLaunch: true, now: now.addingTimeInterval(120))
        let (first, second) = await (launch, foreground)

        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
        XCTAssertEqual(coordinator.startedAutoBackupCount, 1)
        XCTAssertEqual(try autoBackups().count, 1)
        XCTAssertFalse(coordinator.isAutoBackupRunning)
    }

    func test_coordinator_failure_isRecordedInSettingsAndClearedOnSuccess() async throws {
        try insertFixture()
        try AutoBackupService(settings: settings).setFolder(folder)
        settings.autoBackupFrequency = .everyLaunch
        try FileManager.default.removeItem(at: folder)
        let coordinator = BackupCoordinator(settings: settings, backupService: BackupService(settingsDefaults: nil))

        let failed = await coordinator.runAutoBackupIfDue(container: container, isLaunch: true)
        XCTAssertNil(failed)
        XCTAssertNotNil(settings.lastAutoBackupError)
        XCTAssertNil(settings.lastBackupDate)
        XCTAssertFalse(coordinator.isAutoBackupRunning)

        // Map opnieuw gekozen → volgende poging lukt en wist de fout.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try AutoBackupService(settings: settings).setFolder(folder)
        let succeeded = await coordinator.runAutoBackupIfDue(container: container, isLaunch: true)
        XCTAssertNotNil(succeeded)
        XCTAssertNil(settings.lastAutoBackupError)
        XCTAssertNotNil(settings.lastBackupDate)
    }

    func test_coordinator_emptyJournal_skipsAutomaticBackup() async throws {
        try AutoBackupService(settings: settings).setFolder(folder)
        settings.autoBackupFrequency = .everyLaunch
        let coordinator = BackupCoordinator(settings: settings, backupService: BackupService(settingsDefaults: nil))

        let url = await coordinator.runAutoBackupIfDue(container: container, isLaunch: true)
        XCTAssertNil(url)
        XCTAssertEqual(try autoBackups().count, 0)
        XCTAssertNil(settings.lastAutoBackupError)
        XCTAssertNil(settings.lastBackupDate)
    }

    func test_coordinator_notDue_startsNothing() async throws {
        try insertFixture()
        try AutoBackupService(settings: settings).setFolder(folder)
        settings.autoBackupFrequency = .off
        let coordinator = BackupCoordinator(settings: settings, backupService: BackupService(settingsDefaults: nil))

        let url = await coordinator.runAutoBackupIfDue(container: container, isLaunch: true)
        XCTAssertNil(url)
        XCTAssertEqual(coordinator.startedAutoBackupCount, 0)
    }

    // MARK: - BackupViewModel

    func test_viewModel_backgroundManualBackup_presentsShareSheet() async throws {
        try insertFixture()
        let viewModel = BackupViewModel(settings: settings, backupService: BackupService(settingsDefaults: nil))
        await viewModel.createBackup(in: container)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isWorking)
        XCTAssertNil(viewModel.progressMessage)
        let file = try XCTUnwrap(viewModel.shareFile)
        XCTAssertEqual(file.kind, .backup)
        XCTAssertEqual(try BackupService(settingsDefaults: nil).loadBackup(at: file.url).summary.tradeCount, 2)

        // Delen via de share sheet telt nog steeds als backup.
        viewModel.shareSheetFinished(completed: true)
        XCTAssertNotNil(settings.lastBackupDate)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    func test_viewModel_chooseFolder_runsFirstBackupInBackground() async throws {
        try insertFixture()
        let viewModel = BackupViewModel(settings: settings, backupService: BackupService(settingsDefaults: nil))
        let coordinator = BackupCoordinator(settings: settings, backupService: BackupService(settingsDefaults: nil))

        await viewModel.setAutoBackupFolder(folder, coordinator: coordinator, container: container)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(try autoBackups().count, 1)
        XCTAssertEqual(viewModel.autoBackupFrequency, .daily)
        XCTAssertNotNil(viewModel.lastAutoBackupDate)
        XCTAssertFalse(viewModel.isBackupStale)
    }
}
