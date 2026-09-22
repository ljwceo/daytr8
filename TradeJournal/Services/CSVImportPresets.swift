import Foundation

/// Een voorgedefinieerde kolommapping voor een gangbare broker-export.
///
/// Kolommen worden op naam gezocht (hoofdletterongevoelig, spaties rond de
/// naam genegeerd). Een kandidaat als `"Time#2"` betekent: de tweede kolom die
/// `Time` heet — nodig voor MetaTrader-rapporten, waar `Time` en `Price` voor
/// zowel open als close voorkomen.
public struct CSVImportPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let mode: CSVImportMode
    public let dateOrder: ImportDateOrder
    /// Kolomnamen die deze export herkenbaar maken (voor auto-detectie).
    public let identifyingHeaders: [String]
    /// Per veld de mogelijke kolomnamen, in volgorde van voorkeur.
    public let candidates: [CSVImportField: [String]]

    public init(
        id: String,
        name: String,
        mode: CSVImportMode,
        dateOrder: ImportDateOrder = .monthFirst,
        identifyingHeaders: [String],
        candidates: [CSVImportField: [String]]
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.dateOrder = dateOrder
        self.identifyingHeaders = identifyingHeaders
        self.candidates = candidates
    }

    /// Bouwt een `CSVColumnMapping` door de kandidaten tegen `headers` te matchen.
    public func mapping(for headers: [String], timeZoneIdentifier: String = TimeZone.current.identifier) -> CSVColumnMapping {
        var columns: [CSVImportField: Int] = [:]
        for (field, names) in candidates {
            for name in names {
                if let index = Self.columnIndex(of: name, in: headers) {
                    columns[field] = index
                    break
                }
            }
        }
        return CSVColumnMapping(mode: mode, columns: columns, dateOrder: dateOrder, timeZoneIdentifier: timeZoneIdentifier)
    }

    /// Aantal herkenningskolommen dat in `headers` voorkomt, als fractie (0...1).
    public func matchScore(for headers: [String]) -> Double {
        guard !identifyingHeaders.isEmpty else { return 0 }
        let hits = identifyingHeaders.filter { Self.columnIndex(of: $0, in: headers) != nil }.count
        return Double(hits) / Double(identifyingHeaders.count)
    }

    /// Zoekt de index van kolom `name` (optioneel met `#n` voor de n-de
    /// kolom met die naam, 1-based).
    public static func columnIndex(of name: String, in headers: [String]) -> Int? {
        var target = name
        var occurrence = 1
        if let hash = name.lastIndex(of: "#"), let n = Int(name[name.index(after: hash)...]), n > 0 {
            target = String(name[..<hash])
            occurrence = n
        }
        let key = normalize(target)
        var seen = 0
        for (index, header) in headers.enumerated() where normalize(header) == key {
            seen += 1
            if seen == occurrence { return index }
        }
        return nil
    }

    private static func normalize(_ header: String) -> String {
        header.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// De meegeleverde presets (SPEC §9): Tradovate, NinjaTrader, TopstepX/ProjectX,
/// MetaTrader, TradingView, plus het eigen CSV-exportformaat van de app.
///
/// De kolomnamen volgen de standaard-exports van die platforms. Wijkt een
/// export af, dan past de gebruiker de koppeling in het mappingscherm aan.
public enum CSVImportPresets {

    public static let tradeJournal = CSVImportPreset(
        id: "tradejournal",
        name: "TradeJournal (eigen export)",
        mode: .trades,
        identifyingHeaders: ["trade_id", "entry_time", "exit_time", "net_pnl", "r_multiple"],
        candidates: [
            .symbol: ["symbol"],
            .direction: ["direction"],
            .quantity: ["quantity"],
            .entryTime: ["entry_time"],
            .exitTime: ["exit_time"],
            .entryPrice: ["entry_price"],
            .exitPrice: ["exit_price"],
            .stopLoss: ["stop_loss"],
            .takeProfit: ["take_profit"],
            .commission: ["commission"],
            .fees: ["fees"],
            .pnl: ["gross_pnl"],
            .notes: ["notes"]
        ]
    )

    /// Tradovate "Performance"-export: één rij per gematcht koop/verkoop-paar.
    public static let tradovatePerformance = CSVImportPreset(
        id: "tradovate_performance",
        name: "Tradovate (Performance)",
        mode: .trades,
        identifyingHeaders: ["buyFillId", "sellFillId", "boughtTimestamp", "soldTimestamp"],
        candidates: [
            .symbol: ["symbol"],
            .quantity: ["qty"],
            .buyPrice: ["buyPrice"],
            .sellPrice: ["sellPrice"],
            .buyTime: ["boughtTimestamp"],
            .sellTime: ["soldTimestamp"],
            .pnl: ["pnl"]
        ]
    )

    /// Tradovate "Orders"-export: één rij per order, fills worden samengevoegd.
    public static let tradovateOrders = CSVImportPreset(
        id: "tradovate_orders",
        name: "Tradovate (Orders)",
        mode: .fills,
        identifyingHeaders: ["B/S", "Contract", "Fill Time", "avgPrice", "filledQty"],
        candidates: [
            .symbol: ["Contract", "Product"],
            .side: ["B/S"],
            .quantity: ["filledQty", "Filled Qty"],
            .price: ["avgPrice", "Avg Fill Price"],
            .time: ["Fill Time", "Timestamp"],
            .status: ["Status"]
        ]
    )

    /// NinjaTrader 8 "Trades"-grid (Trade Performance → Trades → Export).
    public static let ninjaTraderTrades = CSVImportPreset(
        id: "ninjatrader_trades",
        name: "NinjaTrader (Trades)",
        mode: .trades,
        identifyingHeaders: ["Market pos.", "Entry price", "Exit price", "Entry name", "Exit name"],
        candidates: [
            .symbol: ["Instrument"],
            .direction: ["Market pos.", "Market pos"],
            .quantity: ["Qty", "Quantity"],
            .entryPrice: ["Entry price"],
            .exitPrice: ["Exit price"],
            .entryTime: ["Entry time"],
            .exitTime: ["Exit time"],
            .commission: ["Commission"],
            .pnl: ["Profit"]
        ]
    )

    /// NinjaTrader 8 "Executions"-grid: losse fills.
    public static let ninjaTraderExecutions = CSVImportPreset(
        id: "ninjatrader_executions",
        name: "NinjaTrader (Executions)",
        mode: .fills,
        identifyingHeaders: ["Instrument", "Action", "E/X", "Position"],
        candidates: [
            .symbol: ["Instrument"],
            .side: ["Action"],
            .quantity: ["Quantity", "Qty"],
            .price: ["Price"],
            .time: ["Time"],
            .commission: ["Commission"]
        ]
    )

    /// TopstepX / ProjectX trade-export.
    public static let topstepX = CSVImportPreset(
        id: "topstepx",
        name: "TopstepX / ProjectX",
        mode: .trades,
        identifyingHeaders: ["ContractName", "EnteredAt", "ExitedAt", "EntryPrice", "ExitPrice"],
        candidates: [
            .symbol: ["ContractName", "Contract", "Symbol"],
            .direction: ["Type", "Side"],
            .quantity: ["Size", "Qty", "Quantity"],
            .entryTime: ["EnteredAt", "Entry Time"],
            .exitTime: ["ExitedAt", "Exit Time"],
            .entryPrice: ["EntryPrice", "Entry Price"],
            .exitPrice: ["ExitPrice", "Exit Price"],
            .fees: ["Fees"],
            .commission: ["Commissions", "Commission"],
            .pnl: ["PnL", "P&L"]
        ]
    )

    /// MetaTrader 4/5 accounthistorie ("Positions"-rapport, als CSV opgeslagen).
    public static let metaTrader = CSVImportPreset(
        id: "metatrader",
        name: "MetaTrader 4/5",
        mode: .trades,
        dateOrder: .dayFirst,
        identifyingHeaders: ["S / L", "T / P", "Swap", "Volume", "Profit"],
        candidates: [
            .symbol: ["Symbol", "Item"],
            .direction: ["Type"],
            .quantity: ["Volume", "Size", "Lots"],
            .entryTime: ["Open Time", "Time#1"],
            .exitTime: ["Close Time", "Time#2"],
            .entryPrice: ["Open Price", "Price#1"],
            .exitPrice: ["Close Price", "Price#2"],
            .stopLoss: ["S / L", "S/L", "SL"],
            .takeProfit: ["T / P", "T/P", "TP"],
            .commission: ["Commission"],
            .pnl: ["Profit"]
        ]
    )

    /// TradingView (Paper Trading / broker-panel) orderhistorie.
    public static let tradingView = CSVImportPreset(
        id: "tradingview",
        name: "TradingView",
        mode: .fills,
        identifyingHeaders: ["Symbol", "Side", "Fill Price", "Placing Time", "Closing Time"],
        candidates: [
            .symbol: ["Symbol"],
            .side: ["Side"],
            .quantity: ["Qty", "Quantity"],
            .price: ["Fill Price", "Avg Fill Price", "Price"],
            .time: ["Closing Time", "Fill Time", "Time", "Placing Time"],
            .commission: ["Commission"],
            .status: ["Status"]
        ]
    )

    public static let all: [CSVImportPreset] = [
        tradovatePerformance,
        tradovateOrders,
        ninjaTraderTrades,
        ninjaTraderExecutions,
        topstepX,
        metaTrader,
        tradingView,
        tradeJournal
    ]

    public static func preset(id: String) -> CSVImportPreset? {
        all.first { $0.id == id }
    }

    /// De preset die het best bij `headers` past, of `nil` als geen enkele
    /// preset minstens de helft van zijn herkenningskolommen terugvindt.
    public static func detect(headers: [String]) -> CSVImportPreset? {
        let scored = all.map { ($0, $0.matchScore(for: headers)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 0.5 else { return nil }
        return best.0
    }
}
