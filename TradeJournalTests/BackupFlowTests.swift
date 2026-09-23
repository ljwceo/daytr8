import XCTest
import SwiftData
@testable import TradeJournal

/// Backup-flows zoals ze op het toestel lopen: de share sheet (handmatige
/// backup) en de automatische backup naar een gekozen map.
@MainActor
final class BackupFlowTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var folder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        suiteName = "BackupFlowTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("BackupFlowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        context.insert(Trade(symbol: "NQ", direction: .long, entryDate: Date(), entryPrice: 100, quantity: 1))
        try context.save()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        try super.tearDownWithError()
    }

    private var settings: BackupSettings { BackupSettings(defaults: defaults) }

    private func autoBackups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(AutoBackupService.fileNamePrefix) }
    }

    // MARK: - Share sheet

    /// Bij "Bewaar in Bestanden" sluit de sheet zichzelf: `onDismiss` kan vóór
    /// de completion-handler komen. De backup moet dan toch tellen.
    func test_shareSheet_dismissBeforeCompletion_stillRecordsBackup() {
        let viewModel = BackupViewModel(settings: settings)
        viewModel.createBackup(from: context)
        let file = try? XCTUnwrap(viewModel.shareFile)
        XCTAssertNotNil(file)

        viewModel.shareSheetDismissed()
        XCTAssertNil(viewModel.shareFile)
        viewModel.shareSheetFinished(completed: true)

        XCTAssertNotNil(settings.lastBackupDate)
        XCTAssertFalse(viewModel.isBackupStale)
        if let file { XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path)) }
    }

    func test_shareSheet_completionBeforeDismiss_recordsBackupOnce() {
        let viewModel = BackupViewModel(settings: settings)
        viewModel.createBackup(from: context)
        viewModel.shareSheetFinished(completed: true)
        viewModel.shareSheetDismissed()
        XCTAssertNotNil(settings.lastBackupDate)
    }

    func test_shareSheet_cancelled_doesNotRecordBackup() {
        let viewModel = BackupViewModel(settings: settings)
        viewModel.createBackup(from: context)
        viewModel.shareSheetDismissed()
        viewModel.shareSheetFinished(completed: false)
        XCTAssertNil(settings.lastBackupDate)
        XCTAssertTrue(viewModel.isBackupStale)
    }

    func test_csvExport_doesNotCountAsBackup() {
        let viewModel = BackupViewModel(settings: settings)
        viewModel.exportCSV(from: context)
        viewModel.shareSheetFinished(completed: true)
        XCTAssertNil(settings.lastBackupDate)
    }

    // MARK: - Automatische backup

    func test_chooseFolder_writesFirstBackupImmediately() throws {
        let viewModel = BackupViewModel(settings: settings)
        viewModel.setAutoBackupFolder(folder, context: context)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(try autoBackups().count, 1)
        XCTAssertEqual(viewModel.autoBackupFrequency, .daily)
        XCTAssertNotNil(settings.lastBackupDate)
        XCTAssertNotNil(viewModel.lastAutoBackupDate)
        XCTAssertFalse(viewModel.isBackupStale)
    }

    func test_runIfDue_writesBackupAtLaunchAndRespectsDaily() throws {
        let service = AutoBackupService(settings: settings)
        try service.setFolder(folder)
        settings.autoBackupFrequency = .daily
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        XCTAssertNotNil(service.runIfDue(context: context, isLaunch: true, now: now))
        XCTAssertEqual(try autoBackups().count, 1)
        XCTAssertEqual(settings.lastBackupDate, now)

        // Zelfde dag nog eens: niet opnieuw.
        XCTAssertNil(service.runIfDue(context: context, isLaunch: false, now: now.addingTimeInterval(60)))
        // Een dag later wel.
        XCTAssertNotNil(service.runIfDue(context: context, isLaunch: false, now: now.addingTimeInterval(BackupSettings.dailyInterval + 60)))
        XCTAssertEqual(try autoBackups().count, 2)

        // De backup is een geldige, terug te lezen backup.
        let first = folder.appendingPathComponent(try autoBackups().sorted()[0])
        XCTAssertEqual(try BackupService().loadBackup(at: first).summary.tradeCount, 1)
    }

    func test_failedAutoBackup_isRecordedAndClearedOnSuccess() throws {
        let service = AutoBackupService(settings: settings)
        try service.setFolder(folder)
        settings.autoBackupFrequency = .everyLaunch
        try FileManager.default.removeItem(at: folder)

        XCTAssertNil(service.runIfDue(context: context, isLaunch: true))
        XCTAssertNotNil(settings.lastAutoBackupError)
        XCTAssertNil(settings.lastBackupDate)

        // Map opnieuw gekozen → volgende poging lukt en wist de fout.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try service.setFolder(folder)
        XCTAssertNotNil(service.runIfDue(context: context, isLaunch: true))
        XCTAssertNil(settings.lastAutoBackupError)
    }
}
