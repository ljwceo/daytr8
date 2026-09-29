import XCTest
@testable import TradeJournal

/// Importmap "Op mijn iPhone › Daytr8 › Import": klaarzetten, zoeken en
/// herstelde backups wegzetten — tegen een tijdelijke map i.p.v. Documenten.
final class ImportInboxServiceTests: XCTestCase {

    private var root: URL!
    private var service: ImportInboxService!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory
            .appendingPathComponent("ImportInboxServiceTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        service = ImportInboxService(root: root)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeFile(_ name: String, in directory: URL, contents: String = "x", modified: Date? = nil) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        if let modified { try setModified(modified, of: url) }
        return url
    }

    @discardableResult
    private func makeBackupFolder(_ name: String, in directory: URL, modified: Date? = nil) throws -> URL {
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        try makeFile(BackupService.payloadPath, in: folder, contents: "{}")
        try fileManager.createDirectory(at: folder.appendingPathComponent("images"), withIntermediateDirectories: true)
        if let modified { try setModified(modified, of: folder) }
        return folder
    }

    private func setModified(_ date: Date, of url: URL) throws {
        try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func names(_ candidates: [ImportCandidate]) -> [String] {
        candidates.map(\.name)
    }

    // MARK: - ensureFolder

    func testEnsureFolderCreatesImportFolderAndReadMe() throws {
        try service.ensureFolder()

        var isDirectory: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: service.importFolder.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        let readMe = service.importFolder.appendingPathComponent(ImportInboxService.readMeFileName)
        let text = try String(contentsOf: readMe, encoding: .utf8)
        XCTAssertTrue(text.contains("Backup & herstel"))
    }

    func testEnsureFolderIsIdempotentAndKeepsReadMe() throws {
        try service.ensureFolder()
        let readMe = service.importFolder.appendingPathComponent(ImportInboxService.readMeFileName)
        try Data("eigen tekst".utf8).write(to: readMe)
        try makeFile("backup.zip", in: service.importFolder)

        XCTAssertNoThrow(try service.ensureFolder())

        XCTAssertEqual(try String(contentsOf: readMe, encoding: .utf8), "eigen tekst")
        XCTAssertTrue(fileManager.fileExists(atPath: service.importFolder.appendingPathComponent("backup.zip").path))
    }

    // MARK: - scan

    func testScanFindsZipJsonAndBackupFolder() throws {
        try service.ensureFolder()
        try makeFile("Daytr8-backup.zip", in: service.importFolder)
        try makeFile("backup.json", in: service.importFolder, contents: "{}")
        try makeBackupFolder("Daytr8-backup", in: service.importFolder)

        let candidates = service.scan()

        XCTAssertEqual(Set(names(candidates)), ["Daytr8-backup.zip", "backup.json", "Daytr8-backup"])
        XCTAssertEqual(candidates.first { $0.name == "Daytr8-backup" }?.isFolder, true)
        XCTAssertEqual(candidates.first { $0.name == "Daytr8-backup.zip" }?.isFolder, false)
    }

    func testScanFindsFolderWithBackupOneLevelDeep() throws {
        let outer = service.importFolder.appendingPathComponent("Uitgepakt", isDirectory: true)
        try makeBackupFolder("Daytr8-backup", in: outer)

        XCTAssertEqual(names(service.scan()), ["Uitgepakt"])
    }

    func testScanAlsoLooksInDocumentsRootAndInbox() throws {
        try makeFile("root.zip", in: root)
        try makeFile("gedeeld.zip", in: service.inboxFolder)

        XCTAssertEqual(Set(names(service.scan())), ["root.zip", "gedeeld.zip"])
    }

    func testScanIgnoresNonBackups() throws {
        try service.ensureFolder()
        // Map zonder backup.json.
        try makeFile("foto.png", in: service.importFolder.appendingPathComponent("Leeg", isDirectory: true))
        // Al herstelde backups.
        try makeFile("oud.zip", in: service.restoredFolder)
        try makeBackupFolder("oude-map", in: service.restoredFolder)
        // iCloud-placeholder en verborgen bestand.
        try makeFile(".backup.zip.icloud", in: service.importFolder)
        try makeFile("backup.zip.icloud", in: service.importFolder)
        try makeFile(".verborgen.zip", in: service.importFolder)
        // Andere bestandstypen.
        try makeFile("notitie.txt", in: service.importFolder)

        XCTAssertEqual(service.scan(), [])
    }

    func testScanSortsNewestFirst() throws {
        let now = Date()
        try makeFile("oud.zip", in: service.importFolder, modified: now.addingTimeInterval(-3_600))
        try makeFile("nieuw.zip", in: service.importFolder, modified: now)
        try makeBackupFolder("midden", in: service.importFolder, modified: now.addingTimeInterval(-60))

        XCTAssertEqual(names(service.scan()), ["nieuw.zip", "midden", "oud.zip"])
    }

    func testCandidateForURL() throws {
        let zip = try makeFile("backup.zip", in: service.importFolder)
        let elsewhere = try makeFile("elders.zip", in: root.appendingPathComponent("Anders", isDirectory: true))

        XCTAssertEqual(service.candidate(for: zip)?.name, "backup.zip")
        XCTAssertNil(service.candidate(for: elsewhere))
    }

    // MARK: - markRestored

    func testMarkRestoredMovesToRestoredFolder() throws {
        try makeFile("backup.zip", in: service.importFolder)
        let candidate = try XCTUnwrap(service.scan().first)

        let destination = try service.markRestored(candidate)

        XCTAssertEqual(destination.lastPathComponent, "backup.zip")
        XCTAssertTrue(fileManager.fileExists(atPath: service.restoredFolder.appendingPathComponent("backup.zip").path))
        XCTAssertFalse(fileManager.fileExists(atPath: candidate.url.path))
        XCTAssertEqual(service.scan(), [])
    }

    func testMarkRestoredAvoidsNameCollisions() throws {
        try makeFile("backup.zip", in: service.restoredFolder)
        try makeFile("backup 2.zip", in: service.restoredFolder)
        try makeBackupFolder("map", in: service.restoredFolder)

        try makeFile("backup.zip", in: service.importFolder, contents: "nieuw")
        try makeBackupFolder("map", in: service.importFolder)

        for candidate in service.scan() {
            try service.markRestored(candidate)
        }

        XCTAssertEqual(
            try String(contentsOf: service.restoredFolder.appendingPathComponent("backup 3.zip"), encoding: .utf8),
            "nieuw"
        )
        XCTAssertTrue(fileManager.fileExists(
            atPath: service.restoredFolder.appendingPathComponent("map 2").appendingPathComponent(BackupService.payloadPath).path
        ))
        XCTAssertEqual(service.scan(), [])
    }

    func testMarkRestoredURLIgnoresFilesOutsideInbox() throws {
        let zip = try makeFile("backup.zip", in: service.importFolder)
        let elsewhere = try makeFile("elders.zip", in: root.appendingPathComponent("Anders", isDirectory: true))

        XCTAssertNil(try service.markRestored(url: elsewhere))
        XCTAssertTrue(fileManager.fileExists(atPath: elsewhere.path))

        XCTAssertNotNil(try service.markRestored(url: zip))
        XCTAssertFalse(fileManager.fileExists(atPath: zip.path))
    }
}
