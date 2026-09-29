import XCTest
@testable import TradeJournal

/// Controleert dat de gebouwde Info.plist (uit `project.yml`) de keys bevat
/// om backups via Bestanden / het deelmenu te openen. De tests draaien met de
/// app als host, dus de app-bundle is die van `IncomingFileRouter`.
final class InfoPlistTests: XCTestCase {

    private var info: [String: Any] {
        Bundle(for: IncomingFileRouter.self).infoDictionary ?? [:]
    }

    func testDocumentTypesIncludeZipAndJSON() throws {
        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let contentTypes = documentTypes.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        XCTAssertTrue(contentTypes.contains("public.zip-archive"))
        XCTAssertTrue(contentTypes.contains("public.json"))

        let backupType = try XCTUnwrap(documentTypes.first { ($0["LSItemContentTypes"] as? [String])?.contains("public.zip-archive") == true })
        XCTAssertEqual(backupType["LSHandlerRank"] as? String, "Alternate")
    }

    func testFileSharingEnabled() {
        XCTAssertEqual(info["UIFileSharingEnabled"] as? Bool, true)
    }

    func testDocumentsNotOpenedInPlace() {
        XCTAssertEqual(info["LSSupportsOpeningDocumentsInPlace"] as? Bool, false)
    }
}
