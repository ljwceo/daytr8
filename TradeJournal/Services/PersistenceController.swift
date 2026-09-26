import Foundation
import SwiftData

/// Opent de centrale SwiftData-store van de app.
///
/// - Altijd dezelfde, standaard store (`Application Support/default.store`),
///   zodat een app-update nooit naar een lege database wijst.
/// - Met `AppMigrationPlan`, zodat een nieuwe schemaversie oude data omzet.
/// - Lukt openen met het plan niet (bijv. een migratie die faalt), dan wordt
///   eerst een kopie van de store-bestanden in `StoreRecovery/<tijd>/` gezet
///   en daarna de store zonder plan geopend (het oude gedrag). Er wordt
///   nooit iets gewist.
public enum PersistenceController {

    /// Naam van de map (in Application Support) met herstelkopieën.
    public static let recoveryFolderName = "StoreRecovery"

    /// - Parameter url: alleen voor tests; `nil` = de standaard store van de app.
    public static func makeContainer(url: URL? = nil, fileManager: FileManager = .default) throws -> ModelContainer {
        let schema = Schema(AppSchema.models)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) } ?? ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [configuration])
        } catch {
            #if DEBUG
            print("PersistenceController: openen met migratieplan mislukt: \(error)")
            #endif
            backupStoreFiles(at: configuration.url, fileManager: fileManager)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    /// Kopieert de store en zijn `-wal`/`-shm`-bestanden naar een
    /// herstelmap naast de store. Geeft de map terug (of `nil` als er niets te
    /// kopiëren was).
    @discardableResult
    public static func backupStoreFiles(at storeURL: URL, fileManager: FileManager = .default, now: Date = Date()) -> URL? {
        let candidates = [storeURL, URL(fileURLWithPath: storeURL.path + "-wal"), URL(fileURLWithPath: storeURL.path + "-shm")]
        let existing = candidates.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }

        let folder = storeURL.deletingLastPathComponent()
            .appendingPathComponent(recoveryFolderName, isDirectory: true)
            .appendingPathComponent(CSVExportService.fileTimestamp(now) + "-\(Int(now.timeIntervalSince1970))", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in existing {
                try fileManager.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
            }
            return folder
        } catch {
            #if DEBUG
            print("PersistenceController: herstelkopie mislukt: \(error)")
            #endif
            return nil
        }
    }
}
