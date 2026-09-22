import XCTest
@testable import TradeJournal

final class ZipArchiveTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ZipArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func test_crc32_knownValue() {
        // Standaard testvector voor CRC-32.
        XCTAssertEqual(ZipArchive.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(ZipArchive.crc32(Data()), 0)
    }

    func test_writeAndRead_storedAndDeflated() throws {
        let url = directory.appendingPathComponent("test.zip")
        let text = Data(String(repeating: "TradeJournal backup ", count: 500).utf8)   // comprimeert goed
        let binary = Data((0..<1000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        let empty = Data()

        let writer = try ZipWriter(url: url)
        try writer.addFile(path: "backup.json", data: text, compress: true)
        try writer.addFile(path: "images/ä-éénhoorn.bin", data: binary, compress: false)
        try writer.addFile(path: "leeg.txt", data: empty)
        try writer.finish()

        let fileSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        XCTAssertLessThan(fileSize, text.count, "tekst had gecomprimeerd moeten worden")

        let reader = try ZipReader(url: url)
        XCTAssertEqual(reader.paths, ["backup.json", "images/ä-éénhoorn.bin", "leeg.txt"])
        XCTAssertEqual(try reader.data(for: "backup.json"), text)
        XCTAssertEqual(try reader.data(for: "images/ä-éénhoorn.bin"), binary)
        XCTAssertEqual(try reader.data(for: "leeg.txt"), empty)
        XCTAssertThrowsError(try reader.data(for: "bestaat-niet"))
    }

    func test_reader_rejectsNonZip() {
        XCTAssertThrowsError(try ZipReader(data: Data("geen zip".utf8))) { error in
            XCTAssertEqual(error as? ZipArchive.ZipError, .notAZipFile)
        }
    }

    func test_reader_detectsCorruption() throws {
        let url = directory.appendingPathComponent("corrupt.zip")
        let writer = try ZipWriter(url: url)
        try writer.addFile(path: "a.txt", data: Data("hallo wereld".utf8), compress: false)
        try writer.finish()

        var data = try Data(contentsOf: url)
        // Eerste byte van de inhoud staat direct na de local header (30 bytes + naam).
        data[30 + "a.txt".utf8.count] ^= 0xFF
        let reader = try ZipReader(data: data)
        XCTAssertThrowsError(try reader.data(for: "a.txt")) { error in
            XCTAssertEqual(error as? ZipArchive.ZipError, .checksumMismatch("a.txt"))
        }
    }
}
