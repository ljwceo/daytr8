import XCTest
@testable import TradeJournal

final class ImportValueParserTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: - Getallen

    func test_number_variants() {
        let parser = ImportValueParser()
        XCTAssertEqual(parser.number("1234.5"), 1234.5)
        XCTAssertEqual(parser.number("$1,234.50"), 1234.5)
        XCTAssertEqual(parser.number("-$50.00"), -50)
        XCTAssertEqual(parser.number("$(25.00)"), -25)
        XCTAssertEqual(parser.number("(12.5)"), -12.5)
        XCTAssertEqual(parser.number("1.234,56"), 1234.56)
        XCTAssertEqual(parser.number("1,5"), 1.5)
        XCTAssertEqual(parser.number("0,123"), 0.123)
        XCTAssertEqual(parser.number("1,234"), 1234)
        XCTAssertEqual(parser.number("1.234.567"), 1_234_567)
        XCTAssertEqual(parser.number(" 21450.25 "), 21450.25)
        XCTAssertEqual(parser.number("-7.00"), -7)
        XCTAssertNil(parser.number(""))
        XCTAssertNil(parser.number("n/a"))
    }

    // MARK: - Datums

    func test_date_yearFirstAndISO() {
        let parser = ImportValueParser(timeZone: utc)
        XCTAssertEqual(parser.date("2024-12-05 14:31:22"), utcDate(2024, 12, 5, 14, 31, 22))
        XCTAssertEqual(parser.date("2024.12.05 14:31"), utcDate(2024, 12, 5, 14, 31))
        XCTAssertEqual(parser.date("2024-12-05T14:31:22Z"), utcDate(2024, 12, 5, 14, 31, 22))
        XCTAssertEqual(parser.date("2024-12-05T14:31:22.123456Z"), utcDate(2024, 12, 5, 14, 31, 22))
        XCTAssertEqual(parser.date("2024-12-05T09:31:22-05:00"), utcDate(2024, 12, 5, 14, 31, 22))
        XCTAssertEqual(parser.date("2024-12-05 15:31:22 +0100"), utcDate(2024, 12, 5, 14, 31, 22))
    }

    func test_date_monthFirstAndDayFirst() {
        let us = ImportValueParser(dateOrder: .monthFirst, timeZone: utc)
        XCTAssertEqual(us.date("12/05/2024 09:31:22"), utcDate(2024, 12, 5, 9, 31, 22))
        XCTAssertEqual(us.date("1/2/2024 1:05:00 PM"), utcDate(2024, 1, 2, 13, 5))
        XCTAssertEqual(us.date("1/2/24 12:00:00 AM"), utcDate(2024, 1, 2, 0, 0))

        let eu = ImportValueParser(dateOrder: .dayFirst, timeZone: utc)
        XCTAssertEqual(eu.date("05/12/2024 09:31"), utcDate(2024, 12, 5, 9, 31))
        XCTAssertEqual(eu.date("05.12.2024"), utcDate(2024, 12, 5))
    }

    func test_date_selfCorrectsImpossibleOrder() {
        let us = ImportValueParser(dateOrder: .monthFirst, timeZone: utc)
        XCTAssertEqual(us.date("25/12/2024 10:00"), utcDate(2024, 12, 25, 10, 0))
    }

    func test_date_usesConfiguredTimeZoneWithoutOffset() {
        let ny = TimeZone(identifier: "America/New_York")!
        let parser = ImportValueParser(timeZone: ny)
        // 5 december: EST = UTC-5.
        XCTAssertEqual(parser.date("2024-12-05 09:30:00"), utcDate(2024, 12, 5, 14, 30))
    }

    func test_date_unixTimestamps() {
        let parser = ImportValueParser(timeZone: utc)
        XCTAssertEqual(parser.date("1733409082"), Date(timeIntervalSince1970: 1_733_409_082))
        XCTAssertEqual(parser.date("1733409082000"), Date(timeIntervalSince1970: 1_733_409_082))
    }

    func test_number_decimalCommaPreferred_forSemicolonFiles() {
        let eu = ImportValueParser(prefersDecimalComma: true)
        XCTAssertEqual(eu.number("1,250"), 1.25)
        XCTAssertEqual(eu.number("-46,50"), -46.5)
        XCTAssertEqual(eu.number("1.234,56"), 1234.56)
        XCTAssertEqual(eu.number("102"), 102)
    }

    func test_date_monthNames() {
        let parser = ImportValueParser(timeZone: utc)
        XCTAssertEqual(parser.date("24 sep 2026 14:30"), utcDate(2026, 9, 24, 14, 30))
        XCTAssertEqual(parser.date("24-Sep-2026"), utcDate(2026, 9, 24))
        XCTAssertEqual(parser.date("25 okt. 2026 09:05"), utcDate(2026, 10, 25, 9, 5))
        XCTAssertEqual(parser.date("Sep 24, 2026 2:30 PM"), utcDate(2026, 9, 24, 14, 30))
        XCTAssertEqual(parser.date("Thu, 24 Sep 2026 14:30:00 GMT"), utcDate(2026, 9, 24, 14, 30))
        XCTAssertEqual(parser.date("1 mei 2026"), utcDate(2026, 5, 1))
        XCTAssertNil(parser.date("24 foo 2026"))
    }

    func test_date_invalid() {
        let parser = ImportValueParser(timeZone: utc)
        XCTAssertNil(parser.date(""))
        XCTAssertNil(parser.date("gisteren"))
        XCTAssertNil(parser.date("13/13/2024"))
    }

    // MARK: - Kant / richting

    func test_side_and_direction() {
        let parser = ImportValueParser()
        for text in ["Buy", "B", "BOT", "bought", "Long", "Buy to Cover"] {
            XCTAssertEqual(parser.side(text), .buy, text)
        }
        for text in ["Sell", "S", "SLD", "sold", "Short", "Sell Short"] {
            XCTAssertEqual(parser.side(text), .sell, text)
        }
        XCTAssertNil(parser.side("flat"))
        XCTAssertEqual(parser.direction("Long"), .long)
        XCTAssertEqual(parser.direction("sell"), .short)
    }

    // MARK: - Symbolen

    func test_normalizeSymbol() {
        let known: Set<String> = ["NQ", "MNQ", "ES", "M2K", "EURUSD", "GC"]
        XCTAssertEqual(ImportValueParser.normalizeSymbol("MNQZ4", knownSymbols: known), "MNQ")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("MNQZ24", knownSymbols: known), "MNQ")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("NQH2025", knownSymbols: known), "NQ")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("M2KU5", knownSymbols: known), "M2K")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("/ES", knownSymbols: known), "ES")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("NQ 12-24", knownSymbols: known), "NQ")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("CME_MINI:NQ1!", knownSymbols: known), "NQ")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("COMEX:GCZ2024", knownSymbols: known), "GC")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("eurusd.a", knownSymbols: known), "EURUSD")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("EUR/USD", knownSymbols: known), "EURUSD")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("EURUSDm", knownSymbols: known), "EURUSD")
        XCTAssertEqual(ImportValueParser.normalizeSymbol("aapl", knownSymbols: known), "AAPL")
    }
}
