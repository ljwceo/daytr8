import XCTest
@testable import TradeJournal

/// Backups die via Bestanden / "Deel → Daytr8" binnenkomen (`.onOpenURL`).
@MainActor
final class IncomingFileRouterTests: XCTestCase {

    private var root: URL!
    private var inbox: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IncomingFileRouterTests-\(UUID().uuidString)", isDirectory: true)
        inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testAcceptsZipAndJSONCaseInsensitive() {
        let router = IncomingFileRouter(inboxDirectory: inbox)
        for name in ["TradeJournal-backup-2026-09-29.zip", "backup.json", "BACKUP.ZIP", "Backup.Json"] {
            let url = inbox.appendingPathComponent(name)
            router.receive(url)
            XCTAssertEqual(router.pendingURL, url, name)
            router.consume()
        }
    }

    func testAcceptsFolder() throws {
        let router = IncomingFileRouter(inboxDirectory: inbox)
        let folder = root.appendingPathComponent("TradeJournal-backup", isDirectory: true)
        router.receive(folder)
        XCTAssertEqual(router.pendingURL, folder)

        // Bestaande map zonder "/" aan het eind wordt aan het bestandssysteem herkend.
        router.consume()
        let existing = root.appendingPathComponent("uitgepakt", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let withoutSlash = URL(fileURLWithPath: existing.path)
        XCTAssertTrue(IncomingFileRouter.isSupported(withoutSlash))
    }

    func testIgnoresOtherFilesAndKeepsPending() {
        let router = IncomingFileRouter(inboxDirectory: inbox)
        let zip = inbox.appendingPathComponent("backup.zip")
        router.receive(zip)

        router.receive(inbox.appendingPathComponent("trades.csv"))
        router.receive(inbox.appendingPathComponent("foto.png"))
        router.receive(URL(string: "https://example.com/backup.zip")!)

        XCTAssertEqual(router.pendingURL, zip)
    }

    func testIgnoresUnsupportedWhenEmpty() {
        let router = IncomingFileRouter(inboxDirectory: inbox)
        router.receive(inbox.appendingPathComponent("notitie.txt"))
        XCTAssertNil(router.pendingURL)
    }

    func testConsumeReturnsAndClearsPendingURL() {
        let router = IncomingFileRouter(inboxDirectory: inbox)
        XCTAssertNil(router.consume())

        let url = inbox.appendingPathComponent("backup.zip")
        router.receive(url)
        XCTAssertEqual(router.consume(), url)
        XCTAssertNil(router.pendingURL)
        XCTAssertNil(router.consume())
    }

    func testDiscardRemovesOnlyInboxCopies() throws {
        let router = IncomingFileRouter(inboxDirectory: inbox)
        let inboxCopy = inbox.appendingPathComponent("backup.zip")
        let elsewhere = root.appendingPathComponent("backup.zip")
        try Data("PK".utf8).write(to: inboxCopy)
        try Data("PK".utf8).write(to: elsewhere)

        router.discard(inboxCopy)
        router.discard(elsewhere)

        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxCopy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.path))
    }
}
