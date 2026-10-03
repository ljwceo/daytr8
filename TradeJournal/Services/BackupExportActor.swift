import Foundation
import SwiftData

/// Maakt backups buiten de main thread, met een eigen `ModelContext` op
/// dezelfde `ModelContainer` als de app.
///
/// Gebruikt exact dezelfde `BackupService.exportBackup` als de export op de
/// main thread, dus het formaat (`BackupPayload`, `formatVersion`) is gelijk.
/// Er gaan geen SwiftData-modellen over de actorgrens: alleen URL's, datums
/// en tellingen.
///
/// Maak de actor aan binnen een `Task.detached` (zie `BackupCoordinator`):
/// een `ModelActor` die op de main thread wordt aangemaakt, kan daar ook zijn
/// werk doen.
@ModelActor
actor BackupExportActor {

    /// Wat een automatische backup nodig heeft; op de main actor verzameld
    /// uit `BackupSettings` (die blijft daar).
    struct AutoBackupJob: @unchecked Sendable {
        let service: BackupService
        /// Opgeloste backupmap, `nil` als er geen is of hij onbereikbaar is.
        let folder: URL?
        let hasFolderBookmark: Bool
        let keepCount: Int
        let now: Date
        /// Geen lege backups aanmaken (automatische backup bij app-start).
        let skipIfEmpty: Bool
    }

    /// Aantal trades + daily journals (0 = niets om te backuppen).
    func journalItemCount() -> Int {
        let trades = (try? modelContext.fetchCount(FetchDescriptor<Trade>())) ?? 0
        let journals = (try? modelContext.fetchCount(FetchDescriptor<DailyJournal>())) ?? 0
        return trades + journals
    }

    /// Schrijft een volledige backup-zip naar `directory`.
    func exportBackup(
        service: BackupService,
        to directory: URL = FileManager.default.temporaryDirectory,
        fileNamePrefix: String = "TradeJournal-backup",
        now: Date = Date()
    ) throws -> URL {
        try service.exportBackup(from: modelContext, to: directory, fileNamePrefix: fileNamePrefix, now: now)
    }

    /// Volledige automatische backup: exporteren, naar de gekozen map
    /// kopiëren en oude automatische backups opruimen. `nil` als er niets te
    /// backuppen was (alleen bij `skipIfEmpty`).
    func runAutoBackup(_ job: AutoBackupJob) throws -> URL? {
        if job.skipIfEmpty, journalItemCount() == 0 { return nil }
        guard job.hasFolderBookmark else { throw AutoBackupService.AutoBackupError.noFolder }
        guard let folder = job.folder else { throw AutoBackupService.AutoBackupError.folderUnavailable }
        let temporary = try exportBackup(service: job.service, fileNamePrefix: AutoBackupService.fileNamePrefix, now: job.now)
        return try AutoBackupService.store(temporary, in: folder, keep: job.keepCount)
    }
}

extension BackupExportActor {

    /// Schrijft een backup-zip naar de tijdelijke map (handmatige backup voor
    /// de share sheet), buiten de main thread. Niet-bewaarde wijzigingen in de
    /// `mainContext` worden eerst opgeslagen, zodat de export ze ziet.
    @MainActor
    static func exportInBackground(container: ModelContainer, service: BackupService, now: Date = Date()) async throws -> URL {
        try? container.mainContext.save()
        let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
            let actor = BackupExportActor(modelContainer: container)
            do {
                return .success(try await actor.exportBackup(service: service, now: now))
            } catch {
                return .failure(error)
            }
        }.value
        return try result.get()
    }
}
