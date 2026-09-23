import XCTest
@testable import TradeJournal

final class BackupSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "BackupSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func test_isStale() {
        XCTAssertTrue(BackupSettings.isStale(lastBackup: nil, now: now))
        XCTAssertFalse(BackupSettings.isStale(lastBackup: now.addingTimeInterval(-6 * day), now: now))
        XCTAssertFalse(BackupSettings.isStale(lastBackup: now.addingTimeInterval(-7 * day), now: now))
        XCTAssertTrue(BackupSettings.isStale(lastBackup: now.addingTimeInterval(-7 * day - 1), now: now))
    }

    func test_recordBackup_persistsDates() {
        let settings = BackupSettings(defaults: defaults)
        XCTAssertNil(settings.lastBackupDate)
        XCTAssertTrue(settings.isBackupStale(now: now))

        settings.recordBackup(at: now)
        XCTAssertEqual(settings.lastBackupDate, now)
        XCTAssertNil(settings.lastAutoBackupDate)
        XCTAssertFalse(settings.isBackupStale(now: now))

        settings.recordBackup(at: now, automatic: true)
        XCTAssertEqual(BackupSettings(defaults: defaults).lastAutoBackupDate, now)
    }

    func test_frequencyAndKeepCountDefaults() {
        let settings = BackupSettings(defaults: defaults)
        XCTAssertEqual(settings.autoBackupFrequency, .off)
        XCTAssertEqual(settings.autoBackupKeepCount, BackupSettings.defaultKeepCount)
        settings.autoBackupFrequency = .daily
        settings.autoBackupKeepCount = 0
        XCTAssertEqual(BackupSettings(defaults: defaults).autoBackupFrequency, .daily)
        XCTAssertEqual(settings.autoBackupKeepCount, 1)
    }

    func test_isAutoBackupDue() {
        func due(_ frequency: AutoBackupFrequency, folder: Bool = true, last: Date?, launch: Bool) -> Bool {
            BackupSettings.isAutoBackupDue(frequency: frequency, hasFolder: folder, lastAutoBackup: last, isLaunch: launch, now: now)
        }
        XCTAssertFalse(due(.off, last: nil, launch: true))
        XCTAssertFalse(due(.daily, folder: false, last: nil, launch: true))

        XCTAssertTrue(due(.everyLaunch, last: now, launch: true))
        XCTAssertFalse(due(.everyLaunch, last: nil, launch: false))

        XCTAssertTrue(due(.daily, last: nil, launch: false))
        XCTAssertFalse(due(.daily, last: now.addingTimeInterval(-23 * 3600), launch: true))
        XCTAssertTrue(due(.daily, last: now.addingTimeInterval(-day), launch: false))
    }

    func test_backupsToPrune_keepsNewestAutoBackupsOnly() {
        let files = [
            "TradeJournal-auto-2025-01-03-0900.zip",
            "TradeJournal-auto-2025-01-01-0900.zip",
            "TradeJournal-backup-2024-12-01-1200.zip",   // handmatig: nooit opruimen
            "TradeJournal-auto-2025-01-02-0900.zip",
            "notities.txt"
        ]
        XCTAssertEqual(
            AutoBackupService.backupsToPrune(fileNames: files, keep: 2),
            ["TradeJournal-auto-2025-01-01-0900.zip"]
        )
        XCTAssertEqual(AutoBackupService.backupsToPrune(fileNames: files, keep: 5), [])
    }

    func test_shouldShowReminder_respectsDismissal() {
        XCTAssertTrue(BackupSettings.shouldShowReminder(lastBackup: nil, dismissed: false, now: now))
        XCTAssertFalse(BackupSettings.shouldShowReminder(lastBackup: nil, dismissed: true, now: now))
        XCTAssertFalse(BackupSettings.shouldShowReminder(lastBackup: now.addingTimeInterval(-day), dismissed: false, now: now))

        let settings = BackupSettings(defaults: defaults)
        XCTAssertFalse(settings.isReminderDismissed)
        settings.isReminderDismissed = true
        XCTAssertTrue(BackupSettings(defaults: defaults).isReminderDismissed)
    }

    func test_lastAutoBackupError_emptyMeansNil() {
        let settings = BackupSettings(defaults: defaults)
        XCTAssertNil(settings.lastAutoBackupError)
        settings.lastAutoBackupError = "Map weg"
        XCTAssertEqual(BackupSettings(defaults: defaults).lastAutoBackupError, "Map weg")
        settings.lastAutoBackupError = nil
        XCTAssertNil(settings.lastAutoBackupError)
    }
}
