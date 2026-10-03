import Foundation
import SwiftData
import UniformTypeIdentifiers

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
///
/// `@MainActor`: alle state is UI-state; het zware inlezen van een backup
/// (kopiëren, iCloud-download, uitpakken) loopt in `prepareRestore` los van
/// de main thread.
@MainActor
@Observable
public final class BackupViewModel {

    public var isWorking = false
    /// Tekst bij de voortgangsindicator terwijl een backup op de achtergrond
    /// gemaakt wordt (`nil` = geen tekst).
    public private(set) var progressMessage: String?
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
    /// Tijdelijke werkmap van `pendingRestore` (opgeruimd na herstellen of
    /// annuleren).
    private var pendingWorkDirectory: URL?

    // Gespiegeld uit `BackupSettings` zodat de view automatisch ververst.
    public private(set) var lastBackupDate: Date?
    public private(set) var lastAutoBackupDate: Date?
    public private(set) var autoBackupFolderName: String?
    public private(set) var autoBackupFrequency: AutoBackupFrequency
    public private(set) var isReminderDismissed = false
    public private(set) var lastAutoBackupError: String?

    /// Stap-voor-stap logboek van kiezen en inlezen (Importlogboek).
    public let diagnostics: ImportDiagnosticsLog

    private let settings: BackupSettings
    private let backupService: BackupService
    private let autoBackupService: AutoBackupService
    private let csvExportService: CSVExportService

    public init(
        settings: BackupSettings = BackupSettings(),
        backupService: BackupService = BackupService(),
        csvExportService: CSVExportService = CSVExportService(),
        diagnostics: ImportDiagnosticsLog? = nil
    ) {
        self.settings = settings
        self.backupService = backupService
        self.autoBackupService = AutoBackupService(settings: settings, backupService: backupService)
        self.csvExportService = csvExportService
        self.diagnostics = diagnostics ?? .shared
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

    /// Maakt de backup buiten de main thread (eigen `ModelContext` op
    /// `container`) en toont daarna de share sheet. De view toont zolang een
    /// voortgangsindicator.
    public func createBackup(in container: ModelContainer) async {
        guard !isWorking else { return }
        isWorking = true
        progressMessage = "Backup maken…"
        errorMessage = nil
        statusMessage = nil
        defer {
            isWorking = false
            progressMessage = nil
        }
        do {
            let url = try await BackupExportActor.exportInBackground(container: container, service: backupService)
            present(ShareableFile(url: url, kind: .backup))
        } catch {
            errorMessage = error.localizedDescription
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

    // MARK: - Kiezer

    /// Logt welke knop de bestandskiezer opent.
    public func recordPickerRequest(_ action: String) {
        diagnostics.record("Knop getikt", detail: action)
    }

    /// De gebruiker sloot de kiezer zonder iets te kiezen.
    public func pickerCancelled() {
        errorMessage = nil
        statusMessage = "Geen bestand gekozen."
    }

    /// De kiezer kon niet geopend worden.
    public func pickerFailed(_ error: Error) {
        statusMessage = nil
        errorMessage = error.localizedDescription
    }

    // MARK: - Restore

    /// Leest een gekozen backup in (nog zonder iets te wissen). De view toont
    /// hem daarna met een knop die om bevestiging vraagt.
    ///
    /// `url` mag de `.zip` zijn, maar ook de map die de Bestanden-app ervan
    /// maakt als je op de zip tikt, of alleen `backup.json` daaruit. Alles
    /// wordt eerst naar een eigen tijdelijke map gekopieerd (bij iCloud
    /// gecoördineerd, zodat bestanden eerst gedownload worden) en blijft zo
    /// leesbaar na het sluiten van de security scope. Het kopiëren en
    /// inlezen loopt buiten de main thread, zodat de bestandskiezer kan
    /// sluiten en de voortgang zichtbaar is.
    ///
    /// - Parameter isTemporaryCopy: `url` is een kopie die de kiezer voor ons
    ///   maakte (`asCopy`); die wordt verplaatst i.p.v. gekopieerd.
    public func prepareRestore(from url: URL, isTemporaryCopy: Bool = false) async {
        let name = url.lastPathComponent
        isWorking = true
        errorMessage = nil
        statusMessage = "Bestand ontvangen: \(name) – inlezen…"
        diagnostics.record("Bestand ontvangen", detail: "\(name)\(isTemporaryCopy ? " (kopie van de kiezer)" : "")")

        // Een eerder ingelezen, niet bevestigde backup vervalt.
        discardPendingRestore()

        let didAccess = url.startAccessingSecurityScopedResource()
        diagnostics.record(
            "Security scope",
            detail: didAccess ? "geopend" : "niet nodig of niet gekregen (normaal bij een kopie of lokaal bestand)"
        )

        let job = BackupRestorePreparer.Job(source: url, isTemporaryCopy: isTemporaryCopy, service: backupService)
        let outcome = await Task.detached(priority: .userInitiated) {
            BackupRestorePreparer.run(job)
        }.value

        if didAccess { url.stopAccessingSecurityScopedResource() }
        for note in outcome.notes {
            diagnostics.record(note.step, detail: note.detail)
        }

        switch outcome.result {
        case .success(let backup):
            pendingRestore = backup
            pendingWorkDirectory = outcome.workDirectory
            statusMessage = nil
            let summary = backup.summary
            diagnostics.record(
                "Samenvatting",
                detail: "formaat \(summary.formatVersion), \(summary.tradeCount) trades, \(summary.accountCount) accounts, \(summary.journalCount) journals, \(summary.screenshotCount) screenshots"
            )
        case .failure(let error):
            statusMessage = nil
            errorMessage = "Kon \(name) niet inlezen: \(error.localizedDescription)"
            diagnostics.record(error: error, step: "Fout bij inlezen")
            try? FileManager.default.removeItem(at: outcome.workDirectory)
        }
        isWorking = false
    }

    public func confirmRestore(into context: ModelContext) {
        guard let backup = pendingRestore else { return }
        diagnostics.record("Herstel bevestigd")
        perform {
            let summary = try self.backupService.restore(backup, into: context)
            self.statusMessage = "Backup hersteld: \(summary.tradeCount) trades, \(summary.journalCount) journals, \(summary.screenshotCount) screenshots."
            self.diagnostics.record("Herstel voltooid", detail: "\(summary.tradeCount) trades, \(summary.journalCount) journals, \(summary.screenshotCount) screenshots")
            self.discardPendingRestore()
        }
        if let errorMessage {
            diagnostics.record("Fout bij herstellen", detail: errorMessage)
        }
    }

    public func cancelRestore() {
        if pendingRestore != nil {
            diagnostics.record("Herstel geannuleerd")
        }
        discardPendingRestore()
        isConfirmingRestore = false
    }

    /// Vergeet de ingelezen backup en ruimt zijn tijdelijke werkmap op.
    private func discardPendingRestore() {
        pendingRestore = nil
        if let directory = pendingWorkDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        pendingWorkDirectory = nil
    }

    // MARK: - Automatische backup

    public func setAutoBackupFrequency(_ frequency: AutoBackupFrequency) {
        autoBackupFrequency = frequency
        settings.autoBackupFrequency = frequency
    }

    /// Slaat de gekozen map op en maakt er meteen een eerste backup in —
    /// zo zie je direct of het werkt (anders pas bij de volgende app-start).
    public func setAutoBackupFolder(_ url: URL, context: ModelContext) {
        diagnostics.record("Backupmap gekozen", detail: url.lastPathComponent)
        defer {
            if let errorMessage {
                diagnostics.record("Fout bij instellen backupmap", detail: errorMessage)
            }
        }
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

    /// Als `setAutoBackupFolder(_:context:)`, maar de eerste backup loopt op
    /// de achtergrond via `coordinator` (nooit twee tegelijk).
    func setAutoBackupFolder(_ url: URL, coordinator: BackupCoordinator, container: ModelContainer) async {
        diagnostics.record("Backupmap gekozen", detail: url.lastPathComponent)
        errorMessage = nil
        statusMessage = nil
        do {
            try autoBackupService.setFolder(url)
            if autoBackupFrequency == .off {
                setAutoBackupFrequency(.daily)
            }
            refreshFromSettings()
            let backup = try await runInBackground { try await coordinator.runAutoBackupNow(container: container) }
            statusMessage = "Backupmap ingesteld: \(url.lastPathComponent). Eerste backup opgeslagen als \(backup.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
            diagnostics.record("Fout bij instellen backupmap", detail: error.localizedDescription)
        }
        refreshFromSettings()
    }

    /// "Nu backuppen naar map" op de achtergrond via `coordinator`.
    func runAutoBackupNow(coordinator: BackupCoordinator, container: ModelContainer) async {
        errorMessage = nil
        statusMessage = nil
        do {
            let url = try await runInBackground { try await coordinator.runAutoBackupNow(container: container) }
            statusMessage = "Backup opgeslagen als \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshFromSettings()
    }

    /// Busy-state met voortgangstekst rond een achtergrondbackup.
    private func runInBackground<T>(_ work: () async throws -> T) async throws -> T {
        isWorking = true
        progressMessage = "Backup maken…"
        defer {
            isWorking = false
            progressMessage = nil
        }
        return try await work()
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

// MARK: - Inlezen buiten de main thread

/// Het zware deel van `BackupViewModel.prepareRestore`: iCloud-download
/// aanvragen, kopiëren naar een eigen werkmap en de backup inlezen. Loopt in
/// een `Task.detached`; alles wat het wil loggen komt terug als `notes`.
enum BackupRestorePreparer {

    struct Job: @unchecked Sendable {
        let source: URL
        /// Kopie die de kiezer voor ons maakte (`asCopy`): mag verplaatst worden.
        let isTemporaryCopy: Bool
        let service: BackupService
    }

    struct Note: Sendable {
        let step: String
        let detail: String?
    }

    struct Outcome: @unchecked Sendable {
        let notes: [Note]
        let result: Result<BackupService.LoadedBackup, Error>
        /// Eigen tijdelijke map met de kopie; bij een fout op te ruimen.
        let workDirectory: URL
    }

    static func run(_ job: Job, fileManager: FileManager = .default) -> Outcome {
        var notes: [Note] = []
        func note(_ step: String, _ detail: String? = nil) { notes.append(Note(step: step, detail: detail)) }

        let source = job.source
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)

        do {
            let values = try? source.resourceValues(forKeys: [
                .contentTypeKey, .fileSizeKey, .isDirectoryKey,
                .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
            ])
            let isDirectory = values?.isDirectory ?? false
            let isUbiquitous = values?.isUbiquitousItem ?? false
            note("Bestandsinfo", describe(values, url: source))

            try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            let local = workDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: isDirectory)

            if isUbiquitous {
                requestDownload(of: source, isDirectory: isDirectory, fileManager: fileManager, note: note)
            }

            if job.isTemporaryCopy {
                do {
                    try fileManager.moveItem(at: source, to: local)
                    note("Kopie", "kopie van de kiezer verplaatst naar werkmap")
                } catch {
                    try fileManager.copyItem(at: source, to: local)
                    note("Kopie", "kopie van de kiezer gekopieerd (verplaatsen lukte niet)")
                }
            } else if isUbiquitous || !isInsideAppContainer(source) {
                try coordinatedCopy(from: source, to: local)
                note("Kopie", "gecoördineerd gekopieerd (\(isUbiquitous ? "iCloud" : "extern"))")
            } else {
                try fileManager.copyItem(at: source, to: local)
                note("Kopie", "lokaal gekopieerd")
            }

            // Los gekozen backup.json (niet als kopie): probeer de images-map
            // ernaast mee te nemen (lukt alleen als iOS er toegang toe geeft;
            // anders worden de screenshots bij de restore overgeslagen).
            if !job.isTemporaryCopy, !isDirectory, source.pathExtension.lowercased() == "json" {
                let images = source.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
                let target = workDirectory.appendingPathComponent("images", isDirectory: true)
                do {
                    try coordinatedCopy(from: images, to: target)
                    note("Images naast backup.json", "meegenomen")
                } catch {
                    note("Images naast backup.json", "niet meegenomen: \(ImportDiagnosticsLog.describe(error))")
                }
            }

            let backup = try job.service.loadBackup(at: local)
            note("Archieftype", archiveDescription(backup.reader))
            return Outcome(notes: notes, result: .success(backup), workDirectory: workDirectory)
        } catch {
            return Outcome(notes: notes, result: .failure(error), workDirectory: workDirectory)
        }
    }

    /// Kopieert een bestand of map via `NSFileCoordinator`, zodat iCloud-
    /// bestanden eerst lokaal gedownload worden. Niet op de main thread
    /// aanroepen: dit kan wachten tot de download klaar is.
    static func coordinatedCopy(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
    }

    /// Vraagt iCloud om het item (en bij een map de inhoud) te downloaden.
    /// De gecoördineerde kopie wacht daarna op de download.
    private static func requestDownload(of url: URL, isDirectory: Bool, fileManager: FileManager, note: (String, String?) -> Void) {
        var requested = 0
        var failures: [String] = []
        func request(_ item: URL) {
            let status = (try? item.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
            guard status != .current else { return }
            do {
                try fileManager.startDownloadingUbiquitousItem(at: item)
                requested += 1
            } catch {
                failures.append("\(item.lastPathComponent): \(ImportDiagnosticsLog.describe(error))")
            }
        }
        request(url)
        if isDirectory, let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey]) {
            for case let item as URL in enumerator {
                request(item)
            }
        }
        var detail = "\(requested) item(s) aangevraagd"
        if !failures.isEmpty {
            detail += "; mislukt: " + failures.prefix(3).joined(separator: "; ")
        }
        note("iCloud-download", detail)
    }

    /// Bestand binnen de eigen app-container (tmp, Inbox, Documents)?
    static func isInsideAppContainer(_ url: URL) -> Bool {
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        return path == home || path.hasPrefix(home + "/")
    }

    private static func describe(_ values: URLResourceValues?, url: URL) -> String {
        guard let values else { return "\(url.lastPathComponent): geen bestandsinfo leesbaar" }
        var parts = [url.lastPathComponent]
        parts.append("type \(values.contentType?.identifier ?? "?")")
        if values.isDirectory == true { parts.append("map") }
        if let size = values.fileSize { parts.append("\(size) bytes") }
        if values.isUbiquitousItem == true {
            parts.append("iCloud, download: \(values.ubiquitousItemDownloadingStatus?.rawValue ?? "?")")
        } else {
            parts.append("niet iCloud")
        }
        return parts.joined(separator: ", ")
    }

    private static func archiveDescription(_ archive: BackupArchive) -> String {
        if archive is ZipReader { return "zip" }
        if let folder = archive as? BackupFolder {
            let isLooseJSON = folder.payloadURL.lastPathComponent != BackupService.payloadPath
                || !FileManager.default.fileExists(atPath: folder.root.appendingPathComponent("images").path)
            return isLooseJSON ? "losse backup.json (zonder images-map)" : "uitgepakte map met images"
        }
        return String(describing: type(of: archive))
    }
}
