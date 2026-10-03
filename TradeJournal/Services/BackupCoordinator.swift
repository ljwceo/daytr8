import Foundation
import Observation
import SwiftData

/// Start backups op de achtergrond en zorgt dat er nooit twee automatische
/// backups tegelijk lopen (bijv. app-start en direct daarna `.active`).
///
/// Leeft op app-niveau (`TradeJournalApp`) en wordt via de environment
/// gedeeld met Backup & herstel. Het zware werk (lezen uit SwiftData, JSON,
/// screenshots in de zip, kopiëren naar de map, opruimen) loopt in
/// `BackupExportActor` met een eigen `ModelContext`; `BackupSettings` wordt
/// daarna hier, op de main actor, bijgewerkt, zodat de backupherinnering,
/// de backup-status-widget en Backup & herstel (`@AppStorage`) kloppen.
@MainActor
@Observable
final class BackupCoordinator {

    /// `true` zolang een automatische backup (of "Nu backuppen naar map")
    /// loopt.
    private(set) var isAutoBackupRunning = false

    /// Hoeveel automatische backups er echt gestart zijn (voor tests).
    @ObservationIgnored private(set) var startedAutoBackupCount = 0

    @ObservationIgnored private var autoBackupTask: Task<Result<URL?, Error>, Never>?
    @ObservationIgnored private let settings: BackupSettings
    @ObservationIgnored private let backupService: BackupService
    @ObservationIgnored private let autoBackupService: AutoBackupService

    init(settings: BackupSettings = BackupSettings(), backupService: BackupService = BackupService()) {
        self.settings = settings
        self.backupService = backupService
        self.autoBackupService = AutoBackupService(settings: settings, backupService: backupService)
    }

    // MARK: - Automatische backup

    /// Draait een automatische backup als die volgens de instellingen nodig
    /// is. Loopt er al een, dan wacht deze aanroep op die backup (en start er
    /// geen tweede). Fouten komen in `BackupSettings.lastAutoBackupError`.
    @discardableResult
    func runAutoBackupIfDue(container: ModelContainer, isLaunch: Bool, now: Date = Date()) async -> URL? {
        if let running = autoBackupTask {
            return try? await running.value.get()
        }
        guard settings.isAutoBackupDue(isLaunch: isLaunch, now: now) else { return nil }
        return try? await startAutoBackup(container: container, now: now, skipIfEmpty: true)
    }

    /// Maakt direct een backup in de gekozen map ("Nu backuppen naar map",
    /// map net gekozen). Loopt er al een, dan geeft hij die terug.
    @discardableResult
    func runAutoBackupNow(container: ModelContainer, now: Date = Date()) async throws -> URL {
        let url: URL?
        if let running = autoBackupTask {
            url = try await running.value.get()
        } else {
            url = try await startAutoBackup(container: container, now: now, skipIfEmpty: false)
        }
        guard let url else { throw AutoBackupService.AutoBackupError.folderUnavailable }
        return url
    }

    /// Wacht tot een lopende automatische backup klaar is (bijv. vóór een
    /// restore, die alle data wist).
    func waitForRunningBackup() async {
        if let running = autoBackupTask {
            _ = await running.value
        }
    }

    private func startAutoBackup(container: ModelContainer, now: Date, skipIfEmpty: Bool) async throws -> URL? {
        // Niet-bewaarde wijzigingen eerst opslaan, zodat de eigen context van
        // de achtergrond-export ze ziet.
        try? container.mainContext.save()

        let hasBookmark = settings.autoBackupFolderBookmark != nil
        let job = BackupExportActor.AutoBackupJob(
            service: backupService,
            folder: hasBookmark ? autoBackupService.resolveFolder() : nil,
            hasFolderBookmark: hasBookmark,
            keepCount: settings.autoBackupKeepCount,
            now: now,
            skipIfEmpty: skipIfEmpty
        )

        startedAutoBackupCount += 1
        isAutoBackupRunning = true
        // Synchroon vastgelegd (vóór de eerste `await`), zodat een tweede
        // aanvraag hem altijd ziet.
        let task = Task.detached(priority: .utility) { () -> Result<URL?, Error> in
            let actor = BackupExportActor(modelContainer: container)
            do {
                return .success(try await actor.runAutoBackup(job))
            } catch {
                return .failure(error)
            }
        }
        autoBackupTask = task

        let result = await task.value
        autoBackupTask = nil
        isAutoBackupRunning = false

        switch result {
        case .success(let url):
            if url != nil {
                settings.lastAutoBackupError = nil
                settings.recordBackup(at: now, automatic: true)
            }
            return url
        case .failure(let error):
            settings.lastAutoBackupError = error.localizedDescription
            throw error
        }
    }
}
