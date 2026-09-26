import Foundation

/// Hoe de rijen van een CSV-bestand geïnterpreteerd worden.
public enum CSVImportMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Elke rij is één losse fill (koop of verkoop). Fills worden per symbool
    /// automatisch samengevoegd tot trades.
    case fills
    /// Elke rij is een complete round-trip trade (entry + exit).
    case trades

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fills: return "Losse fills"
        case .trades: return "Complete trades"
        }
    }
}

/// Een veld waar een CSV-kolom aan gekoppeld kan worden.
public enum CSVImportField: String, Codable, CaseIterable, Identifiable, Sendable {
    // Gedeeld
    case symbol
    case quantity
    case commission
    case fees

    // Fills
    case side
    case price
    case time
    case status

    // Trades
    case direction
    case entryTime = "entry_time"
    case exitTime = "exit_time"
    case entryPrice = "entry_price"
    case exitPrice = "exit_price"
    case buyTime = "buy_time"
    case sellTime = "sell_time"
    case buyPrice = "buy_price"
    case sellPrice = "sell_price"
    case stopLoss = "stop_loss"
    case takeProfit = "take_profit"
    case pnl
    /// Netto resultaat na kosten (bijv. `net_pnl` uit de eigen export).
    case netPnL = "net_pnl"
    /// Accountnaam; wordt gekoppeld aan een bestaand account met die naam.
    case account
    /// Stabiele trade-id (eigen export) — voorkomt dubbele trades bij opnieuw importeren.
    case tradeID = "trade_id"
    case notes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .symbol: return "Symbool"
        case .quantity: return "Aantal"
        case .commission: return "Commissie"
        case .fees: return "Fees"
        case .side: return "Koop/verkoop"
        case .price: return "Fill-prijs"
        case .time: return "Fill-tijd"
        case .status: return "Status"
        case .direction: return "Richting (long/short)"
        case .entryTime: return "Entry-tijd"
        case .exitTime: return "Exit-tijd"
        case .entryPrice: return "Entry-prijs"
        case .exitPrice: return "Exit-prijs"
        case .buyTime: return "Koop-tijd"
        case .sellTime: return "Verkoop-tijd"
        case .buyPrice: return "Koop-prijs"
        case .sellPrice: return "Verkoop-prijs"
        case .stopLoss: return "Stop loss"
        case .takeProfit: return "Take profit"
        case .pnl: return "P&L (ter controle)"
        case .netPnL: return "Netto P&L (na kosten)"
        case .account: return "Account"
        case .tradeID: return "Trade-id"
        case .notes: return "Notities"
        }
    }

    /// De velden die in het kolommapping-scherm getoond worden voor `mode`,
    /// in logische volgorde.
    public static func fields(for mode: CSVImportMode) -> [CSVImportField] {
        switch mode {
        case .fills:
            return [.symbol, .side, .quantity, .price, .time, .commission, .fees, .status]
        case .trades:
            return [.symbol, .direction, .quantity,
                    .entryTime, .entryPrice, .exitTime, .exitPrice,
                    .buyTime, .buyPrice, .sellTime, .sellPrice,
                    .stopLoss, .takeProfit, .commission, .fees, .pnl, .netPnL,
                    .account, .tradeID, .notes]
        }
    }
}

/// Koppeling van CSV-kolommen (op index) aan `CSVImportField`s, plus de
/// interpretatie-opties die nodig zijn om de waardes te lezen.
public struct CSVColumnMapping: Equatable, Sendable {
    public var mode: CSVImportMode
    /// Veld → kolomindex in `CSVTable.headers`.
    public var columns: [CSVImportField: Int]
    public var dateOrder: ImportDateOrder
    /// Tijdzone van datums zonder expliciete offset.
    public var timeZoneIdentifier: String

    public init(
        mode: CSVImportMode,
        columns: [CSVImportField: Int] = [:],
        dateOrder: ImportDateOrder = .monthFirst,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.mode = mode
        self.columns = columns
        self.dateOrder = dateOrder
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    public func isMapped(_ field: CSVImportField) -> Bool {
        columns[field] != nil
    }

    /// Nederlandstalige meldingen voor ontbrekende verplichte koppelingen.
    /// Leeg = de mapping is bruikbaar.
    public var validationErrors: [String] {
        var errors: [String] = []
        func require(_ field: CSVImportField) {
            if !isMapped(field) { errors.append("Koppel een kolom aan \"\(field.displayName)\".") }
        }

        require(.symbol)
        switch mode {
        case .fills:
            require(.quantity)
            require(.price)
            require(.time)
        case .trades:
            let hasEntryExit = isMapped(.entryTime) && isMapped(.entryPrice)
            let hasBuySell = isMapped(.buyTime) && isMapped(.sellTime) && isMapped(.buyPrice) && isMapped(.sellPrice)
            if !hasEntryExit && !hasBuySell {
                errors.append("Koppel entry-tijd + entry-prijs (en eventueel exit), of koop-/verkooptijd + koop-/verkoopprijs.")
            }
        }
        return errors
    }
}
