import Foundation

/// Een backup die in de importmap van de app klaarstaat.
public struct ImportCandidate: Identifiable, Equatable {
    /// Het `.zip`-bestand, de `.json` of de (uitgepakte) backupmap.
    public let url: URL
    /// Bestands- of mapnaam zoals in de Bestanden-app.
    public let name: String
    /// Wijzigingsdatum; bepaalt de volgorde (nieuwste eerst).
    public let modified: Date
    public let isFolder: Bool

    public var id: URL { url }

    public init(url: URL, name: String, modified: Date, isFolder: Bool) {
        self.url = url
        self.name = name
        self.modified = modified
        self.isFolder = isFolder
    }
}

/// Importroute zonder documentkiezer: de Documenten-map van de app is (via
/// `UIFileSharingEnabled`) zichtbaar in Bestanden als
/// "Op mijn iPhone › Daytr8". De gebruiker kopieert een backup naar de
/// submap `Import`; de app vindt hem daar met gewone `FileManager`-calls in
/// de eigen sandbox — geen security scope, geen file provider.
///
/// Gevonden backups gaan daarna via `BackupService.loadBackup(at:)` (dat
/// herkent zip, losse json en uitgepakte map zelf).
public struct ImportInboxService {

    public static let importFolderName = "Import"
    public static let restoredFolderName = "Hersteld"
    /// Map waar iOS bestanden neerzet die via "Open in…" binnenkomen.
    public static let inboxFolderName = "Inbox"
    public static let readMeFileName = "LEESMIJ.txt"

    static let readMeText = """
    Daytr8 — backup importeren

    Kopieer hier een Daytr8-backup naartoe: het .zip-bestand, een losse \
    backup.json of de uitgepakte backupmap (met backup.json en images). \
    Met de uitgepakte map komen ook de screenshots mee.

    In Bestanden: houd de backup ingedrukt → Kopieer → ga naar \
    Op mijn iPhone › Daytr8 › Import → houd een lege plek ingedrukt → Plak.

    Open daarna in Daytr8: Meer → Backup & herstel. De backup staat onder \
    "Backups in de Daytr8-map"; tik erop om hem te herstellen. Herstelde \
    backups worden naar de map Hersteld verplaatst.
    """

    /// De Documenten-map van de app.
    public static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Basismap (standaard Documenten); injecteerbaar voor tests.
    public let root: URL
    private let fileManager: FileManager

    public init(root: URL = ImportInboxService.documentsDirectory, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    public var importFolder: URL {
        root.appendingPathComponent(Self.importFolderName, isDirectory: true)
    }

    public var restoredFolder: URL {
        importFolder.appendingPathComponent(Self.restoredFolderName, isDirectory: true)
    }

    public var inboxFolder: URL {
        root.appendingPathComponent(Self.inboxFolderName, isDirectory: true)
    }

    // MARK: - Map klaarzetten

    /// Maakt `Import/` met een `LEESMIJ.txt` aan, zodat de app-map in
    /// Bestanden verschijnt (een lege Documenten-map toont iOS niet).
    /// Idempotent: een bestaande LEESMIJ wordt niet overschreven.
    public func ensureFolder() throws {
        try fileManager.createDirectory(at: importFolder, withIntermediateDirectories: true)
        let readMe = importFolder.appendingPathComponent(Self.readMeFileName)
        if !fileManager.fileExists(atPath: readMe.path) {
            try Data(Self.readMeText.utf8).write(to: readMe, options: .atomic)
        }
    }

    // MARK: - Zoeken

    /// Alle backups in `Import/`, direct in de Documenten-map en in `Inbox/`:
    /// `.zip`- en `.json`-bestanden en mappen met `backup.json` (zelf, of in
    /// een submap één niveau diep). Slaat `Import/Hersteld/`, `LEESMIJ.txt`,
    /// verborgen bestanden en iCloud-placeholders (`.icloud`) over.
    /// Nieuwste eerst.
    public func scan() -> [ImportCandidate] {
        let skippedFolders: Set<String> = [
            Self.normalizedPath(importFolder),
            Self.normalizedPath(restoredFolder),
            Self.normalizedPath(inboxFolder),
        ]

        var seen = Set<String>()
        var result: [ImportCandidate] = []
        for directory in [importFolder, root, inboxFolder] {
            for item in contents(of: directory) {
                let path = Self.normalizedPath(item)
                guard !skippedFolders.contains(path), !seen.contains(path) else { continue }
                guard let candidate = candidate(at: item) else { continue }
                seen.insert(path)
                result.append(candidate)
            }
        }

        return result.sorted {
            if $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// De kandidaat bij `url`, als die in de importmap staat (bijv. om na een
    /// geslaagde restore `markRestored` aan te roepen). `nil` voor bestanden
    /// van elders, zoals een backup die via de documentkiezer gekozen is.
    public func candidate(for url: URL) -> ImportCandidate? {
        let path = Self.normalizedPath(url)
        return scan().first { Self.normalizedPath($0.url) == path }
    }

    // MARK: - Na herstel

    /// Verplaatst een herstelde backup naar `Import/Hersteld/`, zodat hij
    /// niet opnieuw in de lijst staat. Bij een naambotsing krijgt hij een
    /// volgnummer ("backup 2.zip"). Geeft de nieuwe locatie terug.
    @discardableResult
    public func markRestored(_ candidate: ImportCandidate) throws -> URL {
        try fileManager.createDirectory(at: restoredFolder, withIntermediateDirectories: true)
        let destination = uniqueDestination(for: candidate.url.lastPathComponent)
        try fileManager.moveItem(at: candidate.url, to: destination)
        return destination
    }

    /// Als `markRestored(_:)`, maar voor een URL. Staat `url` niet in de
    /// importmap (bijv. gekozen via de documentkiezer), dan gebeurt er niets
    /// en is het resultaat `nil`.
    @discardableResult
    public func markRestored(url: URL) throws -> URL? {
        guard let candidate = candidate(for: url) else { return nil }
        return try markRestored(candidate)
    }

    // MARK: - Intern

    private func contents(of directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func candidate(at url: URL) -> ImportCandidate? {
        let name = url.lastPathComponent
        if name.hasPrefix(".") || name.lowercased().hasSuffix(".icloud") || name == Self.readMeFileName {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }

        if isDirectory.boolValue {
            guard containsBackup(url) else { return nil }
        } else {
            let ext = url.pathExtension.lowercased()
            guard ext == "zip" || ext == "json" else { return nil }
        }

        return ImportCandidate(
            url: url,
            name: name,
            modified: modificationDate(of: url),
            isFolder: isDirectory.boolValue
        )
    }

    /// Map met `backup.json`, zelf of in een directe submap (zoals
    /// `BackupArchiveOpener` die ook opent).
    private func containsBackup(_ folder: URL) -> Bool {
        if hasPayload(folder) { return true }
        return contents(of: folder).contains { child in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: child.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
                && hasPayload(child)
        }
    }

    private func hasPayload(_ folder: URL) -> Bool {
        fileManager.fileExists(atPath: folder.appendingPathComponent(BackupService.payloadPath).path)
    }

    private func modificationDate(of url: URL) -> Date {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date) ?? .distantPast
    }

    private func uniqueDestination(for fileName: String) -> URL {
        var destination = restoredFolder.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: destination.path) else { return destination }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var number = 2
        repeat {
            let name = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            destination = restoredFolder.appendingPathComponent(name)
            number += 1
        } while fileManager.fileExists(atPath: destination.path)
        return destination
    }

    /// Vergelijkbaar pad (symlinks als /var → /private/var opgelost, geen
    /// afsluitende slash).
    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
