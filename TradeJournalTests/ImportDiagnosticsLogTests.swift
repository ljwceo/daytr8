import XCTest
@testable import TradeJournal

@MainActor
final class ImportDiagnosticsLogTests: XCTestCase {

    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent("Diagnostics/import-log.json") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImportDiagnosticsLogTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func test_ringBuffer_keepsOnlyNewestEntries() {
        let log = ImportDiagnosticsLog(fileURL: nil, capacity: 3)
        for index in 1...5 {
            log.record("Stap \(index)")
        }
        XCTAssertEqual(log.entries.map(\.step), ["Stap 3", "Stap 4", "Stap 5"])
    }

    func test_persistence_roundTrip() {
        let log = ImportDiagnosticsLog(fileURL: fileURL)
        log.record("Knop getikt", detail: "Herstel uit backupbestand")
        log.record("Kiezer: geannuleerd")

        let reloaded = ImportDiagnosticsLog(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries.map(\.step), ["Knop getikt", "Kiezer: geannuleerd"])
        XCTAssertEqual(reloaded.entries.first?.detail, "Herstel uit backupbestand")
        XCTAssertEqual(reloaded.entries.map(\.id), log.entries.map(\.id))

        reloaded.clear()
        XCTAssertTrue(ImportDiagnosticsLog(fileURL: fileURL).entries.isEmpty)
    }

    func test_persistence_respectsSmallerCapacityOnLoad() {
        let log = ImportDiagnosticsLog(fileURL: fileURL, capacity: 10)
        for index in 1...6 { log.record("Stap \(index)") }
        let reloaded = ImportDiagnosticsLog(fileURL: fileURL, capacity: 2)
        XCTAssertEqual(reloaded.entries.map(\.step), ["Stap 5", "Stap 6"])
    }

    func test_exportText_hasHeaderWithVersionAndLines() {
        let log = ImportDiagnosticsLog(fileURL: nil, now: { Date(timeIntervalSince1970: 1_750_000_000) })
        log.record("Bestand ontvangen", detail: "backup.zip")
        let text = log.exportText()
        let lines = text.components(separatedBy: "\n")

        XCTAssertTrue(lines[0].contains("importlogboek"))
        XCTAssertEqual(lines[1], "App: \(ImportDiagnosticsLog.appVersionDescription)")
        XCTAssertTrue(ImportDiagnosticsLog.appVersionDescription.hasPrefix("Versie "))
        XCTAssertTrue(ImportDiagnosticsLog.appVersionDescription.contains("(build "))
        XCTAssertEqual(lines[2], "iOS: \(ImportDiagnosticsLog.systemVersion)")
        XCTAssertTrue(text.contains("Regels: 1"))
        XCTAssertTrue(text.contains("Bestand ontvangen — backup.zip"))
    }

    func test_longDetail_isTruncated() {
        let log = ImportDiagnosticsLog(fileURL: nil)
        log.record("Lang", detail: String(repeating: "x", count: ImportDiagnosticsLog.maxDetailLength + 50))
        XCTAssertEqual(log.entries.first?.detail?.count, ImportDiagnosticsLog.maxDetailLength + 1)
    }

    func test_describeError_includesDomainAndCode() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 260)
        XCTAssertTrue(ImportDiagnosticsLog.describe(error).contains("[\(NSCocoaErrorDomain) 260]"))
    }
}
