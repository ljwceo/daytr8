import XCTest
@testable import TradeJournal

final class SessionCalculatorTests: XCTestCase {

    private var ny: TimeZone { TimeZone(identifier: "America/New_York")! }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func test_defaultWindows_coverAllFourSessions() {
        let calc = SessionCalculator.default

        // 10 juli 2024 (dinsdag), NY-tijd
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 21, 0, tz: ny)), .asia,   "21:00 NY hoort in Asia")
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 4,  0, tz: ny)), .london, "04:00 NY hoort in London")
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 9,  30, tz: ny)), .nyAM,  "09:30 NY hoort in NY AM")
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 14, 0, tz: ny)), .nyPM,   "14:00 NY hoort in NY PM")
    }

    func test_boundary_isInclusiveStart_exclusiveEnd() {
        let calc = SessionCalculator.default
        // 08:00 NY hoort in NY AM (start), niet meer in London (einde).
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 8, 0, tz: ny)), .nyAM)
        // 07:59 NY zit nog in London.
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 7, 59, tz: ny)), .london)
    }

    func test_wrappingAsiaWindow_worksAroundMidnight() {
        let calc = SessionCalculator.default
        // 20:00 en 01:30 NY horen beide in Asia.
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 20, 0, tz: ny)), .asia)
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 1,  30, tz: ny)), .asia)
    }

    func test_outsideAllWindows_returnsOther() {
        let calc = SessionCalculator.default
        // 17:30 NY zit tussen NY PM (eindigt 17:00) en Asia (start 20:00) → .other
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 17, 30, tz: ny)), .other)
    }

    func test_amsterdamTime_getsConvertedToConfiguredZone() {
        // Amsterdam 15:00 (zomertijd → CEST = UTC+2) = NY 09:00 → NY AM.
        let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!
        let calc = SessionCalculator.default
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 15, 0, tz: amsterdam)), .nyAM)
    }

    func test_customConfiguration_usesGivenWindows() {
        // Configuratie met alleen één brede London-sessie 07:00-16:00 in UTC.
        let calc = SessionCalculator(
            timeZone: TimeZone(identifier: "UTC")!,
            windows: [.init(session: .london, startHour: 7, endHour: 16)]
        )
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 10, 0, tz: TimeZone(identifier: "UTC")!)), .london)
        XCTAssertEqual(calc.session(for: date(2024, 7, 10, 17, 0, tz: TimeZone(identifier: "UTC")!)), .other)
    }
}
