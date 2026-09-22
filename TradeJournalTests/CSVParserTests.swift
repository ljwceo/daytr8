import XCTest
@testable import TradeJournal

final class CSVParserTests: XCTestCase {

    func test_parse_simpleCommaSeparated() throws {
        let table = try CSVParser.parse("a,b,c\n1,2,3\n4,5,6\n")
        XCTAssertEqual(table.headers, ["a", "b", "c"])
        XCTAssertEqual(table.rows, [["1", "2", "3"], ["4", "5", "6"]])
        XCTAssertEqual(table.delimiter, ",")
    }

    func test_parse_quotedFieldsWithDelimiterQuoteAndNewline() throws {
        let csv = "name,notes\r\n\"NQ, long\",\"zei \"\"wacht\"\"\nop sweep\"\r\n"
        let table = try CSVParser.parse(csv)
        XCTAssertEqual(table.rows.count, 1)
        XCTAssertEqual(table.rows[0][0], "NQ, long")
        XCTAssertEqual(table.rows[0][1], "zei \"wacht\"\nop sweep")
    }

    func test_parse_crlfAndBareCR() throws {
        let table = try CSVParser.parse("a,b\r\n1,2\r3,4")
        XCTAssertEqual(table.rows, [["1", "2"], ["3", "4"]])
    }

    func test_parse_detectsSemicolonAndTab() throws {
        let semicolon = try CSVParser.parse("a;b\n1,5;2\n")
        XCTAssertEqual(semicolon.delimiter, ";")
        XCTAssertEqual(semicolon.rows, [["1,5", "2"]])

        let tab = try CSVParser.parse("a\tb\n1\t2\n")
        XCTAssertEqual(tab.delimiter, "\t")
        XCTAssertEqual(tab.rows, [["1", "2"]])
    }

    func test_parse_stripsBOMAndSkipsEmptyLines() throws {
        let table = try CSVParser.parse("\u{FEFF}symbol,qty\n\nNQ,1\n,\n")
        XCTAssertEqual(table.headers, ["symbol", "qty"])
        XCTAssertEqual(table.rows, [["NQ", "1"]])
    }

    func test_parse_padsAndTruncatesRowsToHeaderWidth() throws {
        let table = try CSVParser.parse("a,b,c\n1\n1,2,3,4\n")
        XCTAssertEqual(table.rows, [["1", "", ""], ["1", "2", "3"]])
    }

    func test_parse_emptyInputThrows() {
        XCTAssertThrowsError(try CSVParser.parse("")) { error in
            XCTAssertEqual(error as? CSVParser.ParseError, .empty)
        }
    }

    func test_parse_dataWindows1252Fallback() throws {
        // "é" in Windows-1252 = 0xE9 (ongeldig als losse UTF-8-byte).
        let data = Data([0x61, 0x0A, 0x63, 0x61, 0x66, 0xE9, 0x0A])
        let table = try CSVParser.parse(data: data)
        XCTAssertEqual(table.rows, [["café"]])
    }

    func test_writer_escapesAndRoundTrips() throws {
        let rows = [["NQ", "long, scalp", "zei \"ja\""], ["ES", "regel1\nregel2", " spatie"]]
        let csv = CSVWriter.write(headers: ["symbol", "notes", "quote"], rows: rows)
        XCTAssertTrue(csv.contains("\"long, scalp\""))
        XCTAssertTrue(csv.contains("\"zei \"\"ja\"\"\""))
        let parsed = try CSVParser.parse(csv)
        XCTAssertEqual(parsed.rows, rows)
    }
}
