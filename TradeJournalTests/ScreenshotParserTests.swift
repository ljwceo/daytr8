import XCTest
import CoreGraphics
@testable import TradeJournal

/// Parser-tests met OCR-tekstfixtures per broker-template (SPEC.md §12), zodat
/// de regexen in `Resources/ScreenshotTemplates/*.json` niet stilletjes stukgaan.
/// De fixtures zijn opgebouwd zoals `ScreenshotLineBuilder` Vision-blokken op
/// één hoogte samenvoegt (label + twee spaties + waarde).
final class ScreenshotParserTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private var templates: [ScreenshotTemplate] { ScreenshotTemplateStore.bundledTemplates() }

    private func makeParser() -> ScreenshotParser {
        ScreenshotParser(templates: templates, timeZone: utc)
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: - Fixtures

    private enum Fixture {
        static let tradovate = """
        Tradovate
        Account  DEMO4471923
        Performance
        Symbol  MNQZ5
        Paired Qty  2
        Buy Price  21,450.25
        Sell Price  21,462.75
        P&L  $50.00
        Bought Timestamp  09/22/2025 09:31:22
        Sold Timestamp  09/22/2025 09:45:10
        Duration  13min 48sec
        Commission  $1.04
        """

        /// Eerst verkocht, later teruggekocht: short.
        static let tradovateShort = """
        Tradovate
        Symbol  ESZ5
        Qty  1
        Buy Price  6650.50
        Sell Price  6655.00
        P&L  $225.00
        Bought Timestamp  09/22/2025 10:12:40
        Sold Timestamp  09/22/2025 10:02:05
        """

        /// Met typografisch minteken (U+2212) zoals Vision dat soms leest.
        static let topstepX = """
        TopstepX
        Trades
        Contract  /MNQ
        Type  Long
        Size  3
        Entry Price  21,450.25
        Exit Price  21,440.00
        Entry Time  09/22/2025 09:31:22
        Exit Time  09/22/2025 09:40:05
        PnL  \u{2212}$61.50
        Fees  $2.22
        """

        static let ninjaTrader = """
        NinjaTrader
        Trade performance
        Instrument  NQ 12-25
        Account  Sim101
        Market pos.  Long
        Qty  1
        Entry price  21450.25
        Exit price  21470.50
        Entry time  9/22/2025 9:31:22 AM
        Exit time  9/22/2025 9:52:10 AM
        Stop  21430.00
        Target  21480.00
        Profit  $405.00
        Commission  $4.30
        """

        static let metaTrader = """
        History
        EURUSD, buy 1.00  270.00
        1.08450 \u{2192} 1.08720
        2025.09.22 11:02:44
        S / L:  1.08200
        T / P:  1.08900
        Open:  2025.09.22 10:15:03
        Close:  2025.09.22 11:02:44
        Commission:  -7.00
        Swap:  -1.20
        """

        /// Echte screenshot: MetaTrader 5 (iOS), tab Geschiedenis, ingeklapte
        /// rijen met twee trades. Geen labels en geen platformnaam in beeld;
        /// "sell 2.5" = richting + lots, de P&L staat rechts op de eerste regel,
        /// de tijd rechts op de tweede is de sluittijd.
        static let metaTrader5History = """
        NAS100 sell 2.5  -169.53
        27722.47 \u{2192} 27799.66  2026.07.29 16:33:04
        NAS100 sell 2.5  183.17
        27615.86 \u{2192} 27532.41  2026.07.29 17:13:04
        """

        /// Echte screenshot: MetaTrader 5 (iOS), langere geschiedenislijst met
        /// buy én sell en bedragen met een spatie als duizendtalscheiding.
        static let metaTrader5HistoryLong = """
        NAS100 buy 10  -109.35
        27173.35 \u{2192} 27160.55  2026.04.24 17:58:32
        NAS100 buy 10  1 040.25
        27175.10 \u{2192} 27296.95  2026.04.24 18:45:06
        NAS100 sell 10  135.78
        27367.60 \u{2192} 27351.65  2026.04.27 15:06:35
        NAS100 buy 20  -541.01
        27045.81 \u{2192} 27014.17  2026.04.28 16:30:05
        NAS100 buy 20  1 492.86
        27026.81 \u{2192} 27114.17  2026.04.28 16:43:37
        NAS100 sell 20  6.15
        27115.92 \u{2192} 27115.56  2026.04.28 16:44:33
        NAS100 buy 10  508.46
        27113.76 \u{2192} 27173.21  2026.04.29 17:41:56
        NAS100 buy 50  1 450.14
        27371.55 \u{2192} 27405.48  2026.04.30 15:22:27
        NAS100 buy 25  -1 044.67
        27300.24 \u{2192} 27251.24  2026.04.30 19:02:27
        NAS100 buy 25  -5.33
        27287.49 \u{2192} 27287.24  2026.04.30 19:09:08
        """

        /// Echte screenshot: MetaTrader 5 (iOS), één opengeklapte trade in de
        /// geschiedenis. P&L rechts op de prijsregel, open → sluittijd op een
        /// eigen regel, S/L-T/P en Swap-Charges in twee kolommen ("-" = leeg).
        static let metaTrader5Expanded = """
        NAS100 buy 50  #119092393
        NAS100 Cash
        27371.55 \u{2192} 27405.48  1 450.14
        \u{0394} = 3393 (0.12%)
        2026.04.30 15:12:01 \u{2192} 2026.04.30 15:22:27
        S/L:  27406.48  Swap:  -
        T/P:  27441.99  Charges:  -
        """

        static let tradingView = """
        TradingView
        Paper Trading
        CME_MINI:MNQ1!
        Short  2
        Avg Fill Price  21,450.25
        Exit Price  21,430.75
        Take Profit  21,400.00
        Stop Loss  21,475.00
        Realized P&L  +$78.00
        Commission  0.00
        Time  2025-09-22 09:31:22
        Close Time  2025-09-22 09:48:01
        """

        /// Onbekend platform: alleen het generieke template.
        static let unknownLayout = """
        Trade summary
        Symbol: GC
        Side: Buy
        Entry: 2650.4
        Exit: 2655.9
        Quantity: 2
        Stop loss: 2645.0
        Net P&L: $1,092.00
        Fees: $8.00
        """

        /// Onbekend platform zonder labels bij het symbool, met twee entry-kandidaten.
        static let unknownWithAlternatives = """
        Order history
        MES  Long
        Entry 6650.25  Exit 6655.50
        Entry 6651.00
        Net P&L $26.25
        """

        static let noTradeData = """
        Hello world
        Nothing to see here
        Battery 87%
        """
    }

    // MARK: - Templates

    func test_bundledTemplates_areLoadedWithOneFallbackAndValidRegexes() {
        let templates = self.templates
        let ids = Set(templates.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["default", "tradovate", "topstepx", "ninjatrader", "metatrader", "tradingview"]), "Gevonden: \(ids)")
        XCTAssertEqual(templates.filter(\.isFallbackTemplate).map(\.id), ["default"])
        XCTAssertEqual(templates.last?.id, "default", "Terugval staat achteraan")
        for template in templates {
            XCTAssertEqual(ScreenshotParser.invalidPatterns(in: template), [], "Ongeldige regex in \(template.id)")
            XCTAssertFalse(template.definedFields.isEmpty, "\(template.id) heeft geen velden")
            if !template.isFallbackTemplate {
                XCTAssertFalse(template.keywords.isEmpty, "\(template.id) heeft geen sleutelwoorden")
            }
        }
    }

    // MARK: - Tradovate

    func test_tradovate_buySellLegsBecomeLongTrade() {
        let result = makeParser().parse(Fixture.tradovate)

        XCTAssertEqual(result.templateID, "tradovate")
        XCTAssertEqual(result.symbol?.value, "MNQ")
        XCTAssertEqual(result.symbol?.source, "Tradovate")
        XCTAssertEqual(result.direction?.value, .long)
        XCTAssertEqual(result.direction?.isDerived, true, "Richting volgt uit koop- vóór verkooptijd")
        XCTAssertEqual(result.entryPrice?.value, 21450.25)
        XCTAssertEqual(result.exitPrice?.value, 21462.75)
        XCTAssertEqual(result.quantity?.value, 2)
        XCTAssertEqual(result.grossPnL?.value, 50)
        XCTAssertNil(result.netPnL, "Tradovate-P&L is bruto; de generieke regex mag hem niet als netto lezen")
        XCTAssertEqual(result.commission?.value, 1.04)
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 9, 22, 9, 31, 22))
        XCTAssertEqual(result.exitTime?.value, utcDate(2025, 9, 22, 9, 45, 10))
    }

    func test_tradovate_sellBeforeBuyIsShort() {
        let result = makeParser().parse(Fixture.tradovateShort)

        XCTAssertEqual(result.symbol?.value, "ES")
        XCTAssertEqual(result.direction?.value, .short)
        XCTAssertEqual(result.entryPrice?.value, 6655.00)
        XCTAssertEqual(result.exitPrice?.value, 6650.50)
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 9, 22, 10, 2, 5))
        XCTAssertEqual(result.exitTime?.value, utcDate(2025, 9, 22, 10, 12, 40))
        XCTAssertEqual(result.grossPnL?.value, 225)
    }

    // MARK: - TopstepX

    func test_topstepX() {
        let result = makeParser().parse(Fixture.topstepX)

        XCTAssertEqual(result.templateID, "topstepx")
        XCTAssertEqual(result.symbol?.value, "MNQ")
        XCTAssertEqual(result.direction?.value, .long)
        XCTAssertEqual(result.direction?.isDerived, false)
        XCTAssertEqual(result.quantity?.value, 3)
        XCTAssertEqual(result.entryPrice?.value, 21450.25)
        XCTAssertEqual(result.exitPrice?.value, 21440.00)
        XCTAssertEqual(result.grossPnL?.value, -61.50, "Typografisch minteken blijft negatief")
        XCTAssertNil(result.netPnL)
        XCTAssertEqual(result.fees?.value, 2.22)
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 9, 22, 9, 31, 22))
        XCTAssertEqual(result.exitTime?.value, utcDate(2025, 9, 22, 9, 40, 5))
    }

    // MARK: - NinjaTrader

    func test_ninjaTrader() {
        let result = makeParser().parse(Fixture.ninjaTrader)

        XCTAssertEqual(result.templateID, "ninjatrader")
        XCTAssertEqual(result.symbol?.value, "NQ", "Expiratie '12-25' valt weg")
        XCTAssertEqual(result.direction?.value, .long)
        XCTAssertEqual(result.quantity?.value, 1)
        XCTAssertEqual(result.entryPrice?.value, 21450.25)
        XCTAssertEqual(result.exitPrice?.value, 21470.50)
        XCTAssertEqual(result.stopLoss?.value, 21430)
        XCTAssertEqual(result.takeProfit?.value, 21480)
        XCTAssertEqual(result.grossPnL?.value, 405)
        XCTAssertEqual(result.commission?.value, 4.30)
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 9, 22, 9, 31, 22))
        XCTAssertEqual(result.exitTime?.value, utcDate(2025, 9, 22, 9, 52, 10))
    }

    // MARK: - MetaTrader

    func test_metaTrader() {
        let result = makeParser().parse(Fixture.metaTrader)

        XCTAssertEqual(result.templateID, "metatrader")
        XCTAssertEqual(result.symbol?.value, "EURUSD")
        XCTAssertEqual(result.direction?.value, .long)
        XCTAssertEqual(result.quantity?.value, 1)
        XCTAssertEqual(result.entryPrice?.value, 1.0845)
        XCTAssertEqual(result.exitPrice?.value, 1.0872)
        XCTAssertEqual(result.stopLoss?.value, 1.082)
        XCTAssertEqual(result.takeProfit?.value, 1.089)
        XCTAssertEqual(result.grossPnL?.value, 270)
        XCTAssertEqual(result.commission?.value, 7, "Commissie wordt positief (postProcess absolute)")
        XCTAssertEqual(result.fees?.value, 1.2, "Negatieve swap is een kost (postProcess negate)")
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 9, 22, 10, 15, 3))
        XCTAssertEqual(result.exitTime?.value, utcDate(2025, 9, 22, 11, 2, 44))
    }

    /// Ingeklapte geschiedenislijst zonder labels: platform herkennen aan de
    /// pijl tussen open- en sluitprijs, de eerste trade is het voorstel, de
    /// volgende komt als alternatief.
    func test_metaTrader5_historyListWithoutLabels() {
        let result = makeParser().parse(Fixture.metaTrader5History)

        XCTAssertEqual(result.templateID, "metatrader")
        XCTAssertEqual(result.symbol?.value, "NAS100")
        XCTAssertEqual(result.direction?.value, .short)
        XCTAssertEqual(result.quantity?.value, 2.5)
        XCTAssertEqual(result.entryPrice?.value, 27722.47)
        XCTAssertEqual(result.entryPrice?.alternatives, [27615.86])
        XCTAssertEqual(result.exitPrice?.value, 27799.66)
        XCTAssertEqual(result.exitPrice?.alternatives, [27532.41])
        XCTAssertEqual(result.grossPnL?.value, -169.53)
        XCTAssertEqual(result.grossPnL?.alternatives, [183.17])
        XCTAssertNil(result.netPnL)
        XCTAssertNil(result.stopLoss)
        XCTAssertNil(result.takeProfit)
        XCTAssertNil(result.entryTime, "De ingeklapte rij toont alleen de sluittijd")
        XCTAssertEqual(result.exitTime?.value, utcDate(2026, 7, 29, 16, 33, 4))
        XCTAssertEqual(result.exitTime?.alternatives, [utcDate(2026, 7, 29, 17, 13, 4)])
    }

    /// Langere lijst: bedragen met spatie als duizendtalscheiding ("1 040.25",
    /// "-1 044.67") blijven hele getallen; de eerste trade is het voorstel.
    func test_metaTrader5_historyListWithThousandsSpaces() {
        let result = makeParser().parse(Fixture.metaTrader5HistoryLong)

        XCTAssertEqual(result.templateID, "metatrader")
        XCTAssertEqual(result.symbol?.value, "NAS100")
        XCTAssertEqual(result.direction?.value, .long)
        XCTAssertEqual(result.direction?.alternatives, [.short])
        XCTAssertEqual(result.quantity?.value, 10)
        XCTAssertEqual(result.quantity?.alternatives, [20, 50, 25])
        XCTAssertEqual(result.entryPrice?.value, 27173.35)
        XCTAssertEqual(result.exitPrice?.value, 27160.55)
        XCTAssertEqual(result.grossPnL?.value, -109.35)
        XCTAssertEqual(result.grossPnL?.alternatives, [1040.25, 135.78, -541.01, 1492.86])
        XCTAssertEqual(result.exitTime?.value, utcDate(2026, 4, 24, 17, 58, 32))
    }

    /// Alleen de rijen met duizendtallen: niet afgekapt tot "1" of "-1".
    func test_metaTrader5_thousandsSpaceInPnL() {
        let text = """
        NAS100 buy 25  -1 044.67
        27300.24 \u{2192} 27251.24  2026.04.30 19:02:27
        NAS100 buy 50  1 450.14
        27371.55 \u{2192} 27405.48  2026.04.30 15:22:27
        """
        let result = makeParser().parse(text)

        XCTAssertEqual(result.grossPnL?.value, -1044.67)
        XCTAssertEqual(result.grossPnL?.alternatives, [1450.14])
    }

    /// Opengeklapte trade: open- en sluittijd, S/L en T/P, P&L op de
    /// prijsregel; lege Swap/Charges ("-") blijven leeg.
    func test_metaTrader5_expandedTrade() {
        let result = makeParser().parse(Fixture.metaTrader5Expanded)

        XCTAssertEqual(result.templateID, "metatrader")
        XCTAssertEqual(result.symbol?.value, "NAS100")
        XCTAssertEqual(result.direction?.value, .long)
        XCTAssertEqual(result.quantity?.value, 50)
        XCTAssertEqual(result.entryPrice?.value, 27371.55)
        XCTAssertEqual(result.exitPrice?.value, 27405.48)
        XCTAssertEqual(result.stopLoss?.value, 27406.48)
        XCTAssertEqual(result.takeProfit?.value, 27441.99)
        XCTAssertEqual(result.grossPnL?.value, 1450.14)
        XCTAssertNil(result.netPnL)
        XCTAssertNil(result.commission)
        XCTAssertNil(result.fees)
        XCTAssertEqual(result.entryTime?.value, utcDate(2026, 4, 30, 15, 12, 1))
        XCTAssertEqual(result.exitTime?.value, utcDate(2026, 4, 30, 15, 22, 27))
    }

    // MARK: - TradingView

    func test_tradingView() {
        let result = makeParser().parse(Fixture.tradingView)

        XCTAssertEqual(result.templateID, "tradingview")
        XCTAssertEqual(result.symbol?.value, "MNQ", "CME_MINI:MNQ1! → MNQ")
        XCTAssertEqual(result.direction?.value, .short)
        XCTAssertEqual(result.quantity?.value, 2)
        XCTAssertEqual(result.entryPrice?.value, 21450.25)
        XCTAssertEqual(result.exitPrice?.value, 21430.75)
        XCTAssertEqual(result.stopLoss?.value, 21475)
        XCTAssertEqual(result.takeProfit?.value, 21400)
        XCTAssertEqual(result.netPnL?.value, 78)
        XCTAssertEqual(result.commission?.value, 0)
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 9, 22, 9, 31, 22))
        XCTAssertEqual(result.exitTime?.value, utcDate(2025, 9, 22, 9, 48, 1))
    }

    // MARK: - Generieke terugval

    func test_unknownLayout_usesGenericTemplate() {
        let result = makeParser().parse(Fixture.unknownLayout)

        XCTAssertNil(result.templateID)
        XCTAssertEqual(result.symbol?.value, "GC")
        XCTAssertEqual(result.symbol?.source, "Generiek")
        XCTAssertEqual(result.direction?.value, .long)
        XCTAssertEqual(result.entryPrice?.value, 2650.4)
        XCTAssertEqual(result.exitPrice?.value, 2655.9)
        XCTAssertEqual(result.quantity?.value, 2)
        XCTAssertEqual(result.stopLoss?.value, 2645)
        XCTAssertEqual(result.netPnL?.value, 1092)
        XCTAssertEqual(result.fees?.value, 8)
        XCTAssertNil(result.entryTime, "'Entry: 2650.4' is geen tijd")
    }

    func test_unknownLayout_symbolHeuristicAndAlternatives() {
        let result = makeParser().parse(Fixture.unknownWithAlternatives)

        XCTAssertEqual(result.symbol?.value, "MES", "Bekend symbool in hoofdletters zonder label")
        XCTAssertEqual(result.direction?.value, .long)
        XCTAssertEqual(result.entryPrice?.value, 6650.25)
        XCTAssertEqual(result.entryPrice?.alternatives, [6651.00])
        XCTAssertEqual(result.entryPrice?.candidates, [6650.25, 6651.00])
        XCTAssertEqual(result.exitPrice?.value, 6655.50)
        XCTAssertEqual(result.netPnL?.value, 26.25)
    }

    func test_noTradeData_isEmpty() {
        let result = makeParser().parse(Fixture.noTradeData)
        XCTAssertNil(result.templateID)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.recognizedFields, [])
    }

    // MARK: - Platform herkennen

    func test_detectBroker_mostKeywordHitsWins() {
        // Tradovate gebruikt TradingView-charts; het TradingView-logo mag
        // Tradovate niet verdringen.
        let text = "TradingView\n" + Fixture.tradovate
        XCTAssertEqual(makeParser().detectBroker(in: text)?.id, "tradovate")
        XCTAssertNil(makeParser().detectBroker(in: Fixture.unknownLayout))
    }

    // MARK: - Tijden

    func test_timeOnly_usesReferenceDay() {
        let parser = makeParser()
        let text = """
        Symbol: NQ
        Entry time: 9:31:22 AM
        Exit time: 14:05
        """
        let result = parser.parse(text, referenceDate: utcDate(2025, 3, 14, 18, 0))
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 3, 14, 9, 31, 22))
        XCTAssertEqual(result.exitTime?.value, utcDate(2025, 3, 14, 14, 5))
    }

    // MARK: - Eigen template zonder code

    func test_newTemplateFromJSON_isUsedWithoutCodeChanges() throws {
        let json = #"""
        {
          "formatVersion": 1,
          "id": "acme",
          "name": "Acme Futures",
          "keywords": ["acme futures"],
          "dateOrder": "day_first",
          "fields": {
            "symbol": { "patterns": ["\\bmarkt\\s*:\\s*([A-Z0-9]+)"] },
            "direction": { "patterns": ["\\bkant\\s*:\\s*(koop|verkoop)"], "postProcess": ["uppercase"] },
            "entry_price": { "patterns": ["\\bin\\s*:\\s*([0-9.,]+)"] },
            "exit_price": { "patterns": ["\\buit\\s*:\\s*([0-9.,]+)"] },
            "net_pnl": { "patterns": ["\\bresultaat\\s*:\\s*(-?[0-9.,]+)"] },
            "entry_time": { "patterns": ["\\bgeopend\\s*:\\s*([0-9/]+ [0-9:]+)"] },
            "unknown_field": { "patterns": ["negeer mij"] }
          }
        }
        """#
        let acme = try ScreenshotTemplateStore.decode(Data(json.utf8))
        let parser = ScreenshotParser(templates: templates + [acme], timeZone: utc)
        let text = """
        ACME FUTURES
        Markt: MESZ5
        Kant: Verkoop
        In: 6650,25
        Uit: 6640,00
        Resultaat: 51,25
        Geopend: 05/10/2025 15:30
        """
        let result = parser.parse(text)

        XCTAssertEqual(result.templateID, "acme")
        XCTAssertEqual(result.symbol?.value, "MES")
        XCTAssertNil(result.direction, "'VERKOOP' is geen bekende richting; geen gok")
        XCTAssertEqual(result.entryPrice?.value, 6650.25)
        XCTAssertEqual(result.exitPrice?.value, 6640.00)
        XCTAssertEqual(result.netPnL?.value, 51.25)
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 10, 5, 15, 30), "day_first uit het template")
        XCTAssertEqual(acme.definedFields.count, 6, "Onbekende sleutels worden genegeerd")
    }

    func test_decode_rejectsNewerFormatVersion() {
        let json = #"{ "formatVersion": 99, "id": "x", "name": "X", "keywords": [], "fields": {} }"#
        XCTAssertThrowsError(try ScreenshotTemplateStore.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ScreenshotTemplateStore.TemplateError, .unsupportedFormatVersion(99))
        }
    }

    func test_invalidRegex_isReportedAndSkipped() {
        let broken = ScreenshotTemplate(
            id: "broken", name: "Broken", keywords: ["broken"],
            fields: ["symbol": .init(patterns: ["([A-Z", #"symbol\s*([A-Z]+)"#])]
        )
        XCTAssertEqual(ScreenshotParser.invalidPatterns(in: broken), ["([A-Z"])
        let result = ScreenshotParser(templates: [broken], timeZone: utc).parse("broken\nSymbol NQ")
        XCTAssertEqual(result.symbol?.value, "NQ")
    }

    // MARK: - Regels uit Vision-blokken

    func test_lineBuilder_mergesBoxesOnSameRow() {
        let boxes = [
            RecognizedTextBox(text: "21,450.25", boundingBox: CGRect(x: 0.6, y: 0.80, width: 0.2, height: 0.03)),
            RecognizedTextBox(text: "Entry Price", boundingBox: CGRect(x: 0.1, y: 0.805, width: 0.3, height: 0.03)),
            RecognizedTextBox(text: "Symbol", boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.2, height: 0.03)),
            RecognizedTextBox(text: "MNQZ5", boundingBox: CGRect(x: 0.6, y: 0.90, width: 0.2, height: 0.03)),
            RecognizedTextBox(text: "  ", boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.1, height: 0.03))
        ]
        XCTAssertEqual(ScreenshotLineBuilder.lines(from: boxes), ["Symbol  MNQZ5", "Entry Price  21,450.25"])
    }
}
