import Foundation
import SwiftData

/// Automatische backup naar een door de gebruiker gekozen map in de
/// Bestanden-app (iCloud Drive, "Op mijn iPhone", een externe provider, ...).
///
/// De map wordt vastgehouden als bookmark (security-scoped URL uit de
/// document picker). Daarvoor is géén entitlement nodig: iOS geeft de app
/// toegang tot precies de map die de gebruiker kiest.
public struct AutoBackupService {

    public enum AutoBackupError: Error, LocalizedError {
        case noFolder
        case folderUnavailable

        public var errorDescription: String? {
            switch self {
            case .noFolder: return "Kies eerst een map voor automatische backups."
            case .folderUnavailable: return "De gekozen backupmap is niet meer bereikbaar. Kies de map opnieuw."
            }
        }
    }

    /// Prefix van automatisch aangemaakte backups; alleen deze bestanden
    /// worden bij het opruimen verwijderd.
    public static let fileNamePrefix = "TradeJournal-auto"

    public let settings: BackupSettings
    public let backupService: BackupService

    public init(settings: BackupSettings = BackupSettings(), backupService: BackupService = BackupService()) {
        self.settings = settings
        self.backupService = backupService
    }

    // MARK: - Map kiezen

    /// Slaat de door de gebruiker gekozen map op als bookmark.
    public func setFolder(_ url: URL) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        settings.autoBackupFolderBookmark = bookmark
        settings.autoBackupFolderName = url.lastPathComponent
    }

    public func clearFolder() {
        settings.autoBackupFolderBookmark = nil
        settings.autoBackupFolderName = nil
        settings.lastAutoBackupError = nil
    }

    /// Lost de bookmark op naar een URL; ververst hem als iOS hem als
    /// verouderd markeert.
    public func resolveFolder() -> URL? {
        guard let bookmark = settings.autoBackupFolderBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            try? setFolder(url)
        }
        return url
    }

    // MARK: - Uitvoeren

    /// Draait een automatische backup als die volgens de instellingen nodig
    /// is. Fouten gooien we hier niet (dit draait bij app-start); ze worden
    /// door `runNow` bewaard in `settings.lastAutoBackupError` en getoond in
    /// de backupherinnering en Backup & herstel.
    @discardableResult
    public func runIfDue(context: ModelContext, isLaunch: Bool, now: Date = Date()) -> URL? {
        guard settings.isAutoBackupDue(isLaunch: isLaunch, now: now) else { return nil }
        // Niets om te backuppen → geen lege backups aanmaken.
        let tradeCount = (try? context.fetchCount(FetchDescriptor<Trade>())) ?? 0
        let journalCount = (try? context.fetchCount(FetchDescriptor<DailyJournal>())) ?? 0
        guard tradeCount + journalCount > 0 else { return nil }
        return try? runNow(context: context, now: now)
    }

    /// Maakt direct een backup in de gekozen map en ruimt oude automatische
    /// backups op (alleen de nieuwste `autoBackupKeepCount` blijven staan).
    @discardableResult
    public func runNow(context: ModelContext, now: Date = Date()) throws -> URL {
        do {
            let url = try writeBackup(context: context, now: now)
            settings.lastAutoBackupError = nil
            return url
        } catch {
            settings.lastAutoBackupError = error.localizedDescription
            throw error
        }
    }

    private func writeBackup(context: ModelContext, now: Date) throws -> URL {
        guard settings.autoBackupFolderBookmark != nil else { throw AutoBackupError.noFolder }
        guard let folder = resolveFolder() else { throw AutoBackupError.folderUnavailable }

        let temporary = try backupService.exportBackup(from: context, fileNamePrefix: Self.fileNamePrefix, now: now)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        let destination = folder.appendingPathComponent(temporary.lastPathComponent)
        try copyCoordinated(from: temporary, to: destination)
        pruneOldBackups(in: folder, keep: settings.autoBackupKeepCount)

        settings.recordBackup(at: now, automatic: true)
        return destination
    }

    // MARK: - Intern

    /// Kopieert via `NSFileCoordinator`, zodat providers als iCloud Drive
    /// correct op de hoogte zijn van de schrijfactie.
    private func copyCoordinated(from source: URL, to destination: URL) throws {
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinatorError) { url in
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.copyItem(at: source, to: url)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
    }

    /// Verwijdert de oudste automatische backups boven `keep`. Bestandsnamen
    /// bevatten een sorteerbare timestamp, dus alfabetisch = chronologisch.
    func pruneOldBackups(in folder: URL, keep: Int) {
        let names = Self.backupsToPrune(
            fileNames: (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [],
            keep: keep
        )
        for name in names {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Pure selectie van de te verwijderen bestanden (testbaar).
    public static func backupsToPrune(fileNames: [String], keep: Int) -> [String] {
        let backups = fileNames
            .filter { $0.hasPrefix(fileNamePrefix) && $0.hasSuffix(".zip") }
            .sorted()
        guard backups.count > keep else { return [] }
        return Array(backups.prefix(backups.count - max(keep, 0)))
    }
}
