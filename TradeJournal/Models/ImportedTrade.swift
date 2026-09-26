import Foundation

/// Eén fill uit een CSV-import, nog los van SwiftData.
public struct ImportedFill: Equatable, Sendable {
    public var symbol: String
    public var date: Date
    public var price: Double
    /// Positief = koop, negatief = verkoop (zelfde conventie als `TradeExecution`).
    public var signedQuantity: Double
    public var commission: Double
    public var fees: Double
    /// Rijnummer in het CSV-bestand (1-based, kopregel niet meegeteld).
    public var sourceRow: Int

    public init(
        symbol: String,
        date: Date,
        price: Double,
        signedQuantity: Double,
        commission: Double = 0,
        fees: Double = 0,
        sourceRow: Int = 0
    ) {
        self.symbol = symbol
        self.date = date
        self.price = price
        self.signedQuantity = signedQuantity
        self.commission = commission
        self.fees = fees
        self.sourceRow = sourceRow
    }
}

/// Een trade zoals hij uit een CSV-import komt, vóórdat hij als `Trade` wordt
/// opgeslagen. Wordt gebruikt voor het voorbeeldscherm en duplicaatdetectie.
public struct ImportedTrade: Equatable, Sendable {
    public var symbol: String
    public var direction: TradeDirection
    /// Totale positiegrootte (som van de entry-fills), altijd positief.
    public var quantity: Double
    public var entryDate: Date
    /// `nil` = de positie is aan het eind van het bestand nog open.
    public var exitDate: Date?
    /// Gewogen gemiddelde entry-prijs.
    public var entryPrice: Double
    /// Gewogen gemiddelde exit-prijs, `nil` voor open trades.
    public var exitPrice: Double?
    public var stopLoss: Double?
    public var takeProfit: Double?
    public var commission: Double
    public var fees: Double
    /// P&L zoals de broker hem rapporteert (alleen ter controle / om de
    /// puntwaarde van onbekende instrumenten af te leiden).
    public var reportedPnL: Double?
    /// Netto resultaat na kosten zoals het bestand het meldt. Wordt bewaard
    /// als het niet uit de prijzen volgt (snelle trades, broker-resultaat).
    public var reportedNetPnL: Double?
    /// Accountnaam uit het bestand (eigen export).
    public var accountName: String?
    /// Trade-id uit het bestand (eigen export).
    public var sourceID: UUID?
    public var notes: String
    /// De fills waaruit de trade is opgebouwd (leeg bij round-trip-imports).
    public var fills: [ImportedFill]
    /// Rijnummers in het CSV-bestand waar deze trade vandaan komt.
    public var sourceRows: [Int]

    public init(
        symbol: String,
        direction: TradeDirection,
        quantity: Double,
        entryDate: Date,
        exitDate: Date? = nil,
        entryPrice: Double,
        exitPrice: Double? = nil,
        stopLoss: Double? = nil,
        takeProfit: Double? = nil,
        commission: Double = 0,
        fees: Double = 0,
        reportedPnL: Double? = nil,
        notes: String = "",
        fills: [ImportedFill] = [],
        sourceRows: [Int] = [],
        reportedNetPnL: Double? = nil,
        accountName: String? = nil,
        sourceID: UUID? = nil
    ) {
        self.symbol = symbol
        self.direction = direction
        self.quantity = quantity
        self.entryDate = entryDate
        self.exitDate = exitDate
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.commission = commission
        self.fees = fees
        self.reportedPnL = reportedPnL
        self.notes = notes
        self.fills = fills
        self.sourceRows = sourceRows
        self.reportedNetPnL = reportedNetPnL
        self.accountName = accountName
        self.sourceID = sourceID
    }

    public var isOpen: Bool { exitDate == nil && exitPrice == nil }

    /// Vingerafdruk voor duplicaatdetectie: symbool, richting, entry-tijd
    /// (op de seconde), aantal en entry-prijs.
    public var fingerprint: String {
        ImportedTrade.fingerprint(
            symbol: symbol,
            direction: direction,
            entryDate: entryDate,
            quantity: quantity,
            entryPrice: entryPrice
        )
    }

    public static func fingerprint(
        symbol: String,
        direction: TradeDirection,
        entryDate: Date,
        quantity: Double,
        entryPrice: Double
    ) -> String {
        let seconds = Int(entryDate.timeIntervalSince1970.rounded())
        return [
            symbol.uppercased(),
            direction.rawValue,
            String(seconds),
            String(format: "%.4f", quantity),
            String(format: "%.6f", entryPrice)
        ].joined(separator: "|")
    }
}
