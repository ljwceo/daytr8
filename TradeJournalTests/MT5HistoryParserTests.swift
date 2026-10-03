import XCTest
import CoreGraphics
@testable import TradeJournal

/// MT5-geschiedenis (iOS-app, History-tab) uit Vision-blokken met posities:
/// bedragen met spaties (ook non-breaking), negatieve bedragen, XAUUSD,
/// forex met vijf decimalen, afgekapte en door elkaar lopende regels.
final class MT5HistoryParserTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private var parser: MT5HistoryParser { MT5HistoryParser(timeZone: utc) }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: - Opbouw van een screenshot

    /// Eén Vision-blok; `y` is het midden (Vision: oorsprong linksonder).
    private func box(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, confidence: Float = 1) -> RecognizedTextBox {
        RecognizedTextBox(text: text, boundingBox: CGRect(x: x, y: y - 0.011, width: width, height: 0.022), confidence: confidence)
    }

    /// Een trade zoals de MT5-lijst hem toont: links symbool/richting/volume
    /// en daaronder de prijzen; rechts de P&L en daaronder de sluittijd.
    private func trade(at y: CGFloat, _ header: String, _ pnl: String?, _ prices: String?, _ time: String?, pnlOffset: CGFloat = 0, confidence: Float = 1) -> [RecognizedTextBox] {
        var boxes = [box(header, x: 0.04, y: y, width: 0.42, confidence: confidence)]
        if let pnl { boxes.append(box(pnl, x: 0.72, y: y + pnlOffset, width: 0.24, confidence: confidence)) }
        if let prices { boxes.append(box(prices, x: 0.04, y: y - 0.034, width: 0.42, confidence: confidence)) }
        if let time { boxes.append(box(time, x: 0.58, y: y - 0.034, width: 0.38, confidence: confidence)) }
        return boxes
    }

    // MARK: - Volledige lijst

    func test_list_forexXauusdAndThousandsSeparators() {
        let boxes = trade(at: 0.80, "AUDCAD sell 0.50", "-12.35", "0.89123 \u{2192} 0.89150", "2026.04.24 17:58:32")
            + trade(at: 0.725, "XAUUSD buy 1.00", "-1 270.65", "2345.67 \u{2192} 2332.96", "2026.04.24 18:45:06")
            + trade(at: 0.65, "EURUSD buy 2", "1\u{00A0}040.25", "1.08350 \u{2192} 1.08870", "2026.04.25 09:01:00")
            + trade(at: 0.575, "GBPJPY sell 0.3", "2\u{202F}118.40", "191.234 \u{2192} 190.180", "2026.04.25 10:15:44")

        let trades = parser.parse(boxes)
        XCTAssertEqual(trades.count, 4)

        let audcad = trades[0]
        XCTAssertEqual(audcad.symbol, "AUDCAD")
        XCTAssertEqual(audcad.direction, .short)
        XCTAssertEqual(audcad.volume, 0.5)
        XCTAssertEqual(audcad.entryPrice, 0.89123)
        XCTAssertEqual(audcad.exitPrice, 0.89150)
        XCTAssertEqual(audcad.pnl, -12.35)
        XCTAssertEqual(audcad.closeTime, date(2026, 4, 24, 17, 58, 32))
        XCTAssertTrue(audcad.isComplete)
        XCTAssertFalse(audcad.isTruncated)
        XCTAssertTrue(audcad.uncertainFields.isEmpty)

        let gold = trades[1]
        XCTAssertEqual(gold.symbol, "XAUUSD")
        XCTAssertEqual(gold.direction, .long)
        XCTAssertEqual(gold.entryPrice, 2345.67)
        XCTAssertEqual(gold.exitPrice, 2332.96)
        XCTAssertEqual(gold.pnl, -1270.65, "spatie als duizendtalscheiding, negatief")

        XCTAssertEqual(trades[2].pnl, 1040.25, "non-breaking space")
        XCTAssertEqual(trades[2].volume, 2)
        XCTAssertEqual(trades[3].pnl, 2118.40, "smalle non-breaking space")
        XCTAssertEqual(trades[3].entryPrice, 191.234)
        XCTAssertEqual(trades[3].direction, .short)
    }

    func test_directionComesFromWord_notColorOrCase() {
        let trades = parser.parse(trade(at: 0.8, "NAS100 SELL 10", "135.78", "27367.60 \u{2192} 27351.65", "2026.04.27 15:06:35")
                                  + trade(at: 0.72, "US30, Buy 0.5", "-3.10", "40100.5 \u{2192} 40094.3", "2026.04.27 16:00:00"))
        XCTAssertEqual(trades.map(\.direction), [.short, .long])
        XCTAssertEqual(trades.map(\.symbol), ["NAS100", "US30"])
    }

    func test_unicodeMinusAndPlusSign() {
        let trades = parser.parse(trade(at: 0.8, "EURUSD buy 0.10", "\u{2212}5.33", "1.08350 \u{2192} 1.08297", "2026.04.25 09:01:00")
                                  + trade(at: 0.72, "EURUSD buy 0.10", "+12.00", "1.08350 \u{2192} 1.08470", "2026.04.25 10:01:00"))
        XCTAssertEqual(trades.map(\.pnl), [-5.33, 12.00])
    }

    // MARK: - Afgekapt

    func test_truncatedAtTop_detailLineWithoutHeader() {
        // Bovenaan is alleen de prijsregel van een trade zichtbaar.
        let boxes = [
            box("27045.81 \u{2192} 27014.17", x: 0.04, y: 0.95, width: 0.42),
            box("2026.04.28 16:30:05", x: 0.58, y: 0.95, width: 0.38)
        ] + trade(at: 0.88, "NAS100 buy 20", "1 492.86", "27026.81 \u{2192} 27114.17", "2026.04.28 16:43:37")

        let trades = parser.parse(boxes)
        XCTAssertEqual(trades.count, 2)
        XCTAssertTrue(trades[0].isTruncated)
        XCTAssertNil(trades[0].symbol)
        XCTAssertNil(trades[0].pnl)
        XCTAssertEqual(trades[0].entryPrice, 27045.81)
        XCTAssertEqual(trades[0].closeTime, date(2026, 4, 28, 16, 30, 5))
        XCTAssertEqual(trades[0].missingFields, [.symbol, .direction, .volume, .pnl])
        XCTAssertFalse(trades[1].isTruncated)
        XCTAssertEqual(trades[1].pnl, 1492.86)
    }

    func test_truncatedAtBottom_headerWithoutDetailLine() {
        let boxes = trade(at: 0.20, "NAS100 buy 25", "-1 044.67", "27300.24 \u{2192} 27251.24", "2026.04.30 19:02:27")
            + trade(at: 0.125, "NAS100 buy 25", "-5.33", nil, nil)
        let trades = parser.parse(boxes)
        XCTAssertEqual(trades.count, 2)
        XCTAssertTrue(trades[1].isTruncated)
        XCTAssertEqual(trades[1].pnl, -5.33)
        XCTAssertNil(trades[1].entryPrice)
        XCTAssertNil(trades[1].closeTime)
        XCTAssertFalse(trades[1].isComplete)
    }

    // MARK: - Door elkaar lopende regels

    func test_pnlSlightlyLowerThanHeader_staysWithItsTrade() {
        // P&L-blok zakt bijna halverwege naar de prijsregel; de prijsregel van
        // de vorige trade en de kop van de volgende staan er vlak bij.
        let boxes = trade(at: 0.80, "NAS100 buy 10", "-109.35", "27173.35 \u{2192} 27160.55", "2026.04.24 17:58:32", pnlOffset: -0.012)
            + trade(at: 0.73, "NAS100 buy 10", "1 040.25", "27175.10 \u{2192} 27296.95", "2026.04.24 18:45:06", pnlOffset: 0.008)
        let trades = parser.parse(boxes)
        XCTAssertEqual(trades.map(\.pnl), [-109.35, 1040.25])
        XCTAssertEqual(trades.map(\.entryPrice), [27173.35, 27175.10])
        XCTAssertEqual(trades.map(\.closeTime), [date(2026, 4, 24, 17, 58, 32), date(2026, 4, 24, 18, 45, 6)])
    }

    func test_mergedBoxes_headerWithPnL_andPricesWithTime() {
        let boxes = [
            box("EURUSD buy 0.10   12.50", x: 0.04, y: 0.80, width: 0.92),
            box("1.08350 \u{2192} 1.08475   2026.04.25 09:01:00", x: 0.04, y: 0.766, width: 0.92),
            box("XAUUSD sell 0.05   -1 270.65", x: 0.04, y: 0.725, width: 0.92),
            box("2345.67 -> 2350.10   2026.04.25 11:30:00", x: 0.04, y: 0.691, width: 0.92)
        ]
        let trades = parser.parse(boxes)
        XCTAssertEqual(trades.count, 2)
        XCTAssertEqual(trades[0].pnl, 12.50)
        XCTAssertEqual(trades[0].exitPrice, 1.08475)
        XCTAssertEqual(trades[0].closeTime, date(2026, 4, 25, 9, 1, 0))
        XCTAssertEqual(trades[1].pnl, -1270.65)
        XCTAssertEqual(trades[1].entryPrice, 2345.67)
        XCTAssertEqual(trades[1].exitPrice, 2350.10)
        XCTAssertTrue(trades.allSatisfy(\.isComplete))
    }

    func test_linesWithoutPositions_realScreenshotFixture() {
        let lines = """
        NAS100 buy 10  -109.35
        27173.35 \u{2192} 27160.55  2026.04.24 17:58:32
        NAS100 buy 10  1 040.25
        27175.10 \u{2192} 27296.95  2026.04.24 18:45:06
        NAS100 sell 10  135.78
        27367.60 \u{2192} 27351.65  2026.04.27 15:06:35
        NAS100 buy 25  -1 044.67
        27300.24 \u{2192} 27251.24  2026.04.30 19:02:27
        """.components(separatedBy: "\n")
        let trades = parser.parse(lines: lines)
        XCTAssertEqual(trades.count, 4)
        XCTAssertEqual(trades.map(\.pnl), [-109.35, 1040.25, 135.78, -1044.67])
        XCTAssertEqual(trades.map(\.direction), [.long, .long, .short, .long])
        XCTAssertEqual(trades.map(\.volume), [10, 10, 10, 25])
        XCTAssertEqual(trades[3].closeTime, date(2026, 4, 30, 19, 2, 27))
        XCTAssertTrue(trades.allSatisfy { $0.isComplete && !$0.isTruncated })
    }

    func test_summaryAndBalanceRowsAreIgnored() {
        let boxes = [
            box("Profit:", x: 0.04, y: 0.95, width: 0.2), box("1 234.56", x: 0.72, y: 0.95, width: 0.24),
            box("Balance:", x: 0.04, y: 0.92, width: 0.2), box("10 000.00", x: 0.72, y: 0.92, width: 0.24)
        ]
            + trade(at: 0.85, "EURUSD buy 1", "100.00", "1.08000 \u{2192} 1.08100", "2026.04.25 09:01:00")
            + [
                // Storting tussen twee trades.
                box("Balance", x: 0.04, y: 0.775, width: 0.2), box("5 000.00", x: 0.72, y: 0.775, width: 0.24),
                box("2026.04.25 09:30:00", x: 0.58, y: 0.741, width: 0.38)
            ]
            + trade(at: 0.70, "EURUSD sell 1", "-50.00", "1.08100 \u{2192} 1.08150", "2026.04.25 10:00:00")
        let trades = parser.parse(boxes)
        XCTAssertEqual(trades.count, 2)
        XCTAssertEqual(trades.map(\.pnl), [100, -50])
        XCTAssertEqual(trades[0].closeTime, date(2026, 4, 25, 9, 1, 0))
        XCTAssertEqual(trades[1].closeTime, date(2026, 4, 25, 10, 0, 0))
    }

    // MARK: - Onzekerheid: markeren, niet gokken

    func test_lowConfidence_marksFields() {
        let trades = parser.parse(trade(at: 0.8, "AUDCAD sell 0.5", "-12.35", "0.89123 \u{2192} 0.89150", "2026.04.24 17:58:32", confidence: 0.3))
        XCTAssertEqual(trades.first?.uncertainFields, Set(MT5ParsedTrade.Field.allCases))
    }

    func test_ocrLetterInNumber_isCorrectedButMarked() {
        let trades = parser.parse(trade(at: 0.8, "NAS100 buy 1O", "1 O40.25", "2717O.35 \u{2192} 27160.55", "2026.04.24 17:58:32"))
        let trade = trades[0]
        XCTAssertEqual(trade.volume, 10)
        XCTAssertEqual(trade.pnl, 1040.25)
        XCTAssertEqual(trade.entryPrice, 27170.35)
        XCTAssertTrue(trade.uncertainFields.isSuperset(of: [.volume, .pnl, .entryPrice, .exitPrice]))
    }

    func test_commaDecimalAmount_isNotGuessed() {
        let trades = parser.parse(trade(at: 0.8, "XAUUSD buy 1.00", "1270,65", "2345.67 \u{2192} 2358.37", "2026.04.24 17:58:32"))
        XCTAssertNil(trades[0].pnl)
        XCTAssertEqual(trades[0].missingFields, [.pnl])
    }

    func test_missingArrow_twoPricesAreMarkedUncertain() {
        let trades = parser.parse(trade(at: 0.8, "EURUSD buy 1", "100.00", "1.08000 1.08100", "2026.04.25 09:01:00"))
        XCTAssertEqual(trades[0].entryPrice, 1.08)
        XCTAssertEqual(trades[0].exitPrice, 1.081)
        XCTAssertTrue(trades[0].uncertainFields.contains(.entryPrice))
    }

    func test_invalidDate_isRejected() {
        XCTAssertNil(parser.parseDateTime("2026.13.01 10:00:00"))
        XCTAssertNil(parser.parseDateTime("2026.04.31 10:00:00"))
        XCTAssertNil(parser.parseDateTime("2026.04.30 25:00:00"))
        XCTAssertEqual(parser.parseDateTime("2026.04.30 19:02:27"), date(2026, 4, 30, 19, 2, 27))
        XCTAssertEqual(parser.parseDateTime("2026.04.30 19:02"), date(2026, 4, 30, 19, 2, 0))
    }

    // MARK: - Getallen

    func test_parseAmount() {
        XCTAssertEqual(MT5HistoryParser.parseAmount("-1 270.65")?.value, -1270.65)
        XCTAssertEqual(MT5HistoryParser.parseAmount("1\u{00A0}270.65")?.value, 1270.65)
        XCTAssertEqual(MT5HistoryParser.parseAmount("-1\u{202F}270.65")?.value, -1270.65)
        XCTAssertEqual(MT5HistoryParser.parseAmount("12 345 678.90")?.value, 12_345_678.90)
        XCTAssertEqual(MT5HistoryParser.parseAmount("\u{2212}5.33")?.value, -5.33)
        XCTAssertEqual(MT5HistoryParser.parseAmount("- 5.33")?.value, -5.33)
        XCTAssertEqual(MT5HistoryParser.parseAmount("+12.00")?.value, 12)
        XCTAssertEqual(MT5HistoryParser.parseAmount("0.00")?.value, 0)
        XCTAssertEqual(MT5HistoryParser.parseAmount("1,270.65")?.value, 1270.65)
        XCTAssertEqual(MT5HistoryParser.parseAmount("1 270.65")?.corrected, false)
        XCTAssertNil(MT5HistoryParser.parseAmount("1270,65"), "komma als decimaal: niet gokken")
        XCTAssertNil(MT5HistoryParser.parseAmount("12 34.5"), "foute groepering")
        XCTAssertNil(MT5HistoryParser.parseAmount("Profit"))
        XCTAssertNil(MT5HistoryParser.parseAmount(""))
        XCTAssertNil(MT5HistoryParser.parseAmount("#119092393x"))
    }

    func test_parsePriceAndVolume() {
        XCTAssertEqual(MT5HistoryParser.parsePrice("0.89123")?.value, 0.89123)
        XCTAssertEqual(MT5HistoryParser.parsePrice("2345.67")?.value, 2345.67)
        XCTAssertEqual(MT5HistoryParser.parsePrice("27173.35")?.value, 27173.35)
        XCTAssertNil(MT5HistoryParser.parsePrice("0"))
        XCTAssertNil(MT5HistoryParser.parsePrice("1,08"))
        XCTAssertEqual(MT5HistoryParser.parseVolume("0.01")?.value, 0.01)
        XCTAssertEqual(MT5HistoryParser.parseVolume("2.5")?.value, 2.5)
        XCTAssertNil(MT5HistoryParser.parseVolume("0,5"))
        XCTAssertNil(MT5HistoryParser.parseVolume("0"))
    }

    func test_emptyInput() {
        XCTAssertTrue(parser.parse([]).isEmpty)
        XCTAssertTrue(parser.parse(lines: ["History", "Positions  Orders  Deals"]).isEmpty)
    }
}
