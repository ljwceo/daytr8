import XCTest
@testable import TradeJournal

final class DecimalInputTests: XCTestCase {

    func test_parse_acceptsCommaAndDot() {
        XCTAssertEqual(DecimalInput.parse("18000,25"), 18_000.25)
        XCTAssertEqual(DecimalInput.parse("18000.25"), 18_000.25)
        XCTAssertEqual(DecimalInput.parse(" 5 "), 5)
        XCTAssertEqual(DecimalInput.parse(",5"), 0.5)
        XCTAssertEqual(DecimalInput.parse("-2,5"), -2.5)
    }

    func test_parse_trailingSeparatorWhileTyping() {
        XCTAssertEqual(DecimalInput.parse("18000,"), 18_000)
    }

    func test_parse_rejectsInvalid() {
        XCTAssertNil(DecimalInput.parse(""))
        XCTAssertNil(DecimalInput.parse(","))
        XCTAssertNil(DecimalInput.parse("1,2,3"))
        XCTAssertNil(DecimalInput.parse("abc"))
    }

    func test_format_usesLocaleWithoutGrouping() {
        let dutch = Locale(identifier: "nl_NL")
        XCTAssertEqual(DecimalInput.format(18_000.25, locale: dutch), "18000,25")
        XCTAssertEqual(DecimalInput.format(0.25, locale: Locale(identifier: "en_US")), "0.25")
        XCTAssertEqual(DecimalInput.format(0, locale: dutch), "")
        XCTAssertEqual(DecimalInput.parse(DecimalInput.format(12_345.678, locale: dutch)), 12_345.678)
    }
}
