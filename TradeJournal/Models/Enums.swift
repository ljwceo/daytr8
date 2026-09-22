import Foundation

/// Type van een handelsaccount. Bepaalt of trades meetellen in de "live" statistieken.
public enum AccountType: String, Codable, CaseIterable, Identifiable, Sendable {
    case propFirm = "prop_firm"
    case live
    case demo
    case backtest

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .propFirm: return "Prop firm"
        case .live: return "Live"
        case .demo: return "Demo"
        case .backtest: return "Backtest"
        }
    }

    /// Backtest-accounts vervuilen de live statistieken niet.
    public var countsInLiveStats: Bool {
        self != .backtest
    }
}

/// Richting van een trade.
public enum TradeDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case long
    case short

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .long: return "Long"
        case .short: return "Short"
        }
    }

    /// +1 voor long, -1 voor short — handig voor P&L-berekeningen.
    public var sign: Double {
        switch self {
        case .long: return 1
        case .short: return -1
        }
    }
}

/// Handelssessie zoals gebruikt door ICT/SMC-traders.
/// Bepaald op basis van de tijd van de entry en een instelbare tijdzone.
public enum Session: String, Codable, CaseIterable, Identifiable, Sendable {
    case asia
    case london
    case nyAM = "ny_am"
    case nyPM = "ny_pm"
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .asia: return "Asia"
        case .london: return "London"
        case .nyAM: return "NY AM"
        case .nyPM: return "NY PM"
        case .other: return "Overig"
        }
    }
}

/// Categorie waarin een confluence valt (voor de gegroepeerde selectiechips).
public enum ConfluenceCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case bias
    case pdArrays = "pd_arrays"
    case liquidity
    case structure
    case time
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bias: return "Bias"
        case .pdArrays: return "PD Arrays"
        case .liquidity: return "Liquiditeit"
        case .structure: return "Structuur"
        case .time: return "Tijd"
        case .other: return "Overig"
        }
    }

    /// Standaardkleur (hex) voor chips in deze categorie.
    public var defaultColorHex: String {
        switch self {
        case .bias: return "#4C8BF5"
        case .pdArrays: return "#A46BF5"
        case .liquidity: return "#F5A64C"
        case .structure: return "#26B87F"
        case .time: return "#E0554D"
        case .other: return "#9AA0A6"
        }
    }
}

/// Categorie van een instrument. Wordt gebruikt om standaardwaarden af te leiden
/// en filters in de rapportage aan te bieden.
public enum InstrumentCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case future
    case microFuture = "micro_future"
    case forex
    case stock
    case crypto
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .future: return "Future"
        case .microFuture: return "Micro future"
        case .forex: return "Forex"
        case .stock: return "Aandelen"
        case .crypto: return "Crypto"
        case .other: return "Overig"
        }
    }
}

/// Resultaat van een trade in categorie-vorm — handig voor statistieken en filters.
public enum TradeOutcome: String, Codable, CaseIterable, Sendable {
    case win
    case loss
    case breakeven
    case open
}
