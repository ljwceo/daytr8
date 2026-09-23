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
    /// De sheet-binding zet hem weer op `nil` bij het sluiten.
    public var shareFile: ShareableFile?

    /// Het gedeelde bestand tot de share sheet zijn resultaat meldt. Los van
    /// `shareFile`: bij "Bewaar in Bestanden" sluit de sheet zichzelf en kan
    /// SwiftUI's `onDismiss` vóór de completion-handler komen — die mag de
    /// backup dan niet meer kwijt zijn.
    private var inFlightShare: ShareableFile?

    /// Een ingelezen backup die op bevestiging wacht.
    public private(set) var pendingRestore: BackupService.LoadedBackup?
    public var isConfirmingRestore = false

    // Gespiegeld uit `BackupSettings` zodat de view automatisch ververst.
    public private(set) var lastBackupDate: Date?
    public private(set) var lastAutoBackupDate: Date?
    public private(set) var autoBackupFolderName: String?
    public private(set) var autoBackupFrequency: AutoBackupFrequency
    public private(set) var isReminderDismissed = false
    public private(set) var lastAutoBackupError: String?

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

    /// Backupherinnering (banner op het dashboard) weer aan- of uitzetten.
    public func setReminderEnabled(_ enabled: Bool) {
        settings.isReminderDismissed = !enabled
        isReminderDismissed = !enabled
    }

    public var hasAutoBackupFolder: Bool { autoBackupFolderName != nil }

    // MARK: - Handmatige backup

    public func createBackup(from context: ModelContext) {
        perform {
            let url = try self.backupService.exportBackup(from: context)
            self.present(ShareableFile(url: url, kind: .backup))
        }
    }

    /// Resultaat van de share sheet (completion-handler van
    /// `UIActivityViewController`). Alleen een voltooide actie (bijv.
    /// "Bewaar in Bestanden") telt als geslaagde backup. Werkt ongeacht of de
    /// sheet al gesloten is (`shareSheetDismissed`).
    public func shareSheetFinished(completed: Bool) {
        guard let file = inFlightShare else { return }
        if completed && file.kind == .backup {
            settings.recordBackup()
            statusMessage = "Backup bewaard."
            refreshFromSettings()
        }
        try? FileManager.default.removeItem(at: file.url)
        inFlightShare = nil
        shareFile = nil
    }

    /// De sheet is gesloten. Het resultaat volgt via `shareSheetFinished`;
    /// hier dus niets opruimen of als mislukt markeren.
    public func shareSheetDismissed() {
        shareFile = nil
    }

    private func present(_ file: ShareableFile) {
        if let previous = inFlightShare, previous.url != file.url {
            try? FileManager.default.removeItem(at: previous.url)
        }
        inFlightShare = file
        shareFile = file
    }

    // MARK: - CSV-export

    public func exportCSV(from context: ModelContext) {
        perform {
            let trades = try context.fetch(FetchDescriptor<Trade>())
            let url = try self.csvExportService.exportFile(for: trades)
            self.present(ShareableFile(url: url, kind: .csv))
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

    /// Slaat de gekozen map op en maakt er meteen een eerste backup in —
    /// zo zie je direct of het werkt (anders pas bij de volgende app-start).
    public func setAutoBackupFolder(_ url: URL, context: ModelContext) {
        perform {
            defer { self.refreshFromSettings() }
            try self.autoBackupService.setFolder(url)
            if self.autoBackupFrequency == .off {
                self.setAutoBackupFrequency(.daily)
            }
            let backup = try self.autoBackupService.runNow(context: context)
            self.statusMessage = "Backupmap ingesteld: \(url.lastPathComponent). Eerste backup opgeslagen als \(backup.lastPathComponent)."
        }
    }

    public func clearAutoBackupFolder() {
        autoBackupService.clearFolder()
        setAutoBackupFrequency(.off)
        refreshFromSettings()
    }

    public func runAutoBackupNow(from context: ModelContext) {
        perform {
            defer { self.refreshFromSettings() }
            let url = try self.autoBackupService.runNow(context: context)
            self.statusMessage = "Backup opgeslagen als \(url.lastPathComponent)."
        }
    }

    // MARK: - Intern

    public func refreshFromSettings() {
        lastBackupDate = settings.lastBackupDate
        lastAutoBackupDate = settings.lastAutoBackupDate
        isReminderDismissed = settings.isReminderDismissed
        lastAutoBackupError = settings.lastAutoBackupError
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
