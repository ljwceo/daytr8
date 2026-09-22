import Foundation
import SwiftData

/// Een bestand dat via de share sheet gedeeld / in Bestanden bewaard wordt.
public struct ShareableFile: Identifiable, Equatable {
    public enum Kind: Equatable {
        case backup
        case csv
    }

    public let url: URL
    public let kind: Kind
    public var id: URL { url }
}

/// Viewmodel achter `BackupView`: handmatige backup, restore, automatische
/// backup naar een map in Bestanden en CSV-export.
@Observable
public final class BackupViewModel {

    public var isWorking = false
    public var statusMessage: String?
    public var errorMessage: String?

    /// Gezet na het maken van een backup/CSV → view toont de share sheet.
    public var shareFile: ShareableFile?

    /// Een ingelezen backup die op bevestiging wacht.
    public private(set) var pendingRestore: BackupService.LoadedBackup?
    public var isConfirmingRestore = false

    // Gespiegeld uit `BackupSettings` zodat de view automatisch ververst.
    public private(set) var lastBackupDate: Date?
    public private(set) var lastAutoBackupDate: Date?
    public private(set) var autoBackupFolderName: String?
    public private(set) var autoBackupFrequency: AutoBackupFrequency

    private let settings: BackupSettings
    private let backupService: BackupService
    private let autoBackupService: AutoBackupService
    private let csvExportService: CSVExportService

    public init(
        settings: BackupSettings = BackupSettings(),
        backupService: BackupService = BackupService(),
        csvExportService: CSVExportService = CSVExportService()
    ) {
        self.settings = settings
        self.backupService = backupService
        self.autoBackupService = AutoBackupService(settings: settings, backupService: backupService)
        self.csvExportService = csvExportService
        self.autoBackupFrequency = settings.autoBackupFrequency
        refreshFromSettings()
    }

    public var isBackupStale: Bool {
        BackupSettings.isStale(lastBackup: lastBackupDate)
    }

    public var hasAutoBackupFolder: Bool { autoBackupFolderName != nil }

    // MARK: - Handmatige backup

    public func createBackup(from context: ModelContext) {
        perform {
            let url = try self.backupService.exportBackup(from: context)
            self.shareFile = ShareableFile(url: url, kind: .backup)
        }
    }

    /// Aangeroepen als de share sheet sluit. Alleen een voltooide actie
    /// (bijv. "Bewaar in Bestanden") telt als geslaagde backup.
    public func shareSheetFinished(completed: Bool) {
        guard let file = shareFile else { return }
        if completed && file.kind == .backup {
            settings.recordBackup()
            statusMessage = "Backup bewaard."
            refreshFromSettings()
        }
        try? FileManager.default.removeItem(at: file.url)
        shareFile = nil
    }

    // MARK: - CSV-export

    public func exportCSV(from context: ModelContext) {
        perform {
            let trades = try context.fetch(FetchDescriptor<Trade>())
            let url = try self.csvExportService.exportFile(for: trades)
            self.shareFile = ShareableFile(url: url, kind: .csv)
        }
    }

    // MARK: - Restore

    /// Leest een gekozen backup in (nog zonder iets te wissen) en vraagt om
    /// bevestiging. Het bestand wordt eerst naar de tijdelijke map gekopieerd
    /// zodat het na het sluiten van de security scope leesbaar blijft.
    public func prepareRestore(from url: URL) {
        perform {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let local = FileManager.default.temporaryDirectory
                .appendingPathComponent("restore-\(UUID().uuidString).zip")
            try FileManager.default.copyItem(at: url, to: local)
            self.pendingRestore = try self.backupService.loadBackup(at: local)
            self.isConfirmingRestore = true
        }
    }

    public func confirmRestore(into context: ModelContext) {
        guard let backup = pendingRestore else { return }
        perform {
            let summary = try self.backupService.restore(backup, into: context)
            self.statusMessage = "Backup hersteld: \(summary.tradeCount) trades, \(summary.journalCount) journals, \(summary.screenshotCount) screenshots."
            self.pendingRestore = nil
        }
    }

    public func cancelRestore() {
        pendingRestore = nil
        isConfirmingRestore = false
    }

    // MARK: - Automatische backup

    public func setAutoBackupFrequency(_ frequency: AutoBackupFrequency) {
        autoBackupFrequency = frequency
        settings.autoBackupFrequency = frequency
    }

    public func setAutoBackupFolder(_ url: URL) {
        perform {
            try self.autoBackupService.setFolder(url)
            if self.autoBackupFrequency == .off {
                self.setAutoBackupFrequency(.daily)
            }
            self.refreshFromSettings()
            self.statusMessage = "Backupmap ingesteld: \(url.lastPathComponent)."
        }
    }

    public func clearAutoBackupFolder() {
        autoBackupService.clearFolder()
        setAutoBackupFrequency(.off)
        refreshFromSettings()
    }

    public func runAutoBackupNow(from context: ModelContext) {
        perform {
            let url = try self.autoBackupService.runNow(context: context)
            self.refreshFromSettings()
            self.statusMessage = "Backup opgeslagen als \(url.lastPathComponent)."
        }
    }

    // MARK: - Intern

    public func refreshFromSettings() {
        lastBackupDate = settings.lastBackupDate
        lastAutoBackupDate = settings.lastAutoBackupDate
        autoBackupFolderName = settings.autoBackupFolderBookmark == nil ? nil : settings.autoBackupFolderName
    }

    /// Voert `work` uit met busy-state en nette foutmelding.
    private func perform(_ work: () throws -> Void) {
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        defer { isWorking = false }
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
