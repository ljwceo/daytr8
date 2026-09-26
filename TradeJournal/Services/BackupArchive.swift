import Foundation

/// Een bron waaruit een backup gelezen wordt: het `.zip`-bestand zelf, of de
/// inhoud ervan nadat de Bestanden-app hem heeft uitgepakt (een map met
/// `backup.json` en `images/`, of alleen `backup.json`).
///
/// Paden zijn relatief, zoals in de zip (`backup.json`, `images/<naam>`).
public protocol BackupArchive {
    func contains(_ path: String) -> Bool
    func data(for path: String) throws -> Data
}

extension ZipReader: BackupArchive {}

/// Een uitgepakte backup op schijf.
public struct BackupFolder: BackupArchive {

    /// Map met (eventueel) `images/`.
    public let root: URL
    /// Het JSON-bestand met de payload; standaard `root/backup.json`, maar
    /// een los gekozen bestand mag ook anders heten (bijv. "backup 2.json").
    public let payloadURL: URL

    public init(root: URL, payloadURL: URL? = nil) {
        self.root = root
        self.payloadURL = payloadURL ?? root.appendingPathComponent(BackupService.payloadPath)
    }

    public func contains(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: path).path)
    }

    public func data(for path: String) throws -> Data {
        try Data(contentsOf: url(for: path), options: .mappedIfSafe)
    }

    private func url(for path: String) -> URL {
        path == BackupService.payloadPath ? payloadURL : root.appendingPathComponent(path)
    }
}

public enum BackupArchiveOpener {

    /// Opent `url` als backup, herkend aan de inhoud en niet aan de extensie:
    /// - een map met `backup.json` (of een map daarboven, één niveau diep);
    /// - een zip-bestand (magic bytes `PK`), ook zonder `.zip`-extensie;
    /// - een los JSON-bestand; afbeeldingen worden dan in een `images/`-map
    ///   ernaast gezocht (ontbreken ze, dan worden ze bij de restore overgeslagen).
    public static func open(_ url: URL, fileManager: FileManager = .default) throws -> BackupArchive {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }

        if isDirectory.boolValue {
            if let folder = folder(at: url, fileManager: fileManager) { return folder }
            // Bijv. de map waarin de uitgepakte backupmap staat.
            let children = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for child in children.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                if let folder = folder(at: child, fileManager: fileManager) { return folder }
            }
            throw BackupService.BackupError.missingPayload
        }

        let handle = try FileHandle(forReadingFrom: url)
        let head = (try? handle.read(upToCount: 4)) ?? Data()
        try? handle.close()
        if head.starts(with: [0x50, 0x4B]) {
            return try ZipReader(url: url)
        }
        return BackupFolder(root: url.deletingLastPathComponent(), payloadURL: url)
    }

    private static func folder(at url: URL, fileManager: FileManager) -> BackupFolder? {
        let payload = url.appendingPathComponent(BackupService.payloadPath)
        guard fileManager.fileExists(atPath: payload.path) else { return nil }
        return BackupFolder(root: url)
    }
}
