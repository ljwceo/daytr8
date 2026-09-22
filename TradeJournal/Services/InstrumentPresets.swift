import Foundation
import SwiftData

/// Standaardinstrumenten die bij de eerste app-start worden aangemaakt.
///
/// Waarden komen uit de officiële specs van CME (equity index / metals / energy futures)
/// en de gebruikelijke forex-conventies (5-decimals JPY-paren zijn 0.001 tick).
///
/// Elke preset is bewerkbaar (naam, tick size, tick value) én uitbreidbaar
/// door de gebruiker via de instellingen; presets zijn te herkennen aan
/// `isBuiltIn == true`.
public enum InstrumentPresets {

    /// Definitie van één preset zonder direct een `@Model` te instantiëren
    /// (handig voor unit tests en voor het bouwen van seed-data zonder context).
    public struct Definition: Equatable, Sendable {
        public let symbol: String
        public let name: String
        public let category: InstrumentCategory
        public let tickSize: Double
        public let tickValue: Double
        public let currency: String
        public let defaultQuantity: Double
        public let sortOrder: Int

        public init(
            symbol: String,
            name: String,
            category: InstrumentCategory,
            tickSize: Double,
            tickValue: Double,
            currency: String = "USD",
            defaultQuantity: Double = 1,
            sortOrder: Int
        ) {
            self.symbol = symbol
            self.name = name
            self.category = category
            self.tickSize = tickSize
            self.tickValue = tickValue
            self.currency = currency
            self.defaultQuantity = defaultQuantity
            self.sortOrder = sortOrder
        }
    }

    /// Volledige lijst met meegeleverde presets.
    /// Toevoegingen komen onderaan zodat bestaande installaties `sortOrder` behouden.
    public static let all: [Definition] = [
        // Equity-index futures (CME)
        .init(symbol: "NQ",  name: "E-mini Nasdaq-100",         category: .future,       tickSize: 0.25,    tickValue: 5.00, sortOrder: 10),
        .init(symbol: "MNQ", name: "Micro E-mini Nasdaq-100",   category: .microFuture,  tickSize: 0.25,    tickValue: 0.50, sortOrder: 20),
        .init(symbol: "ES",  name: "E-mini S&P 500",            category: .future,       tickSize: 0.25,    tickValue: 12.50, sortOrder: 30),
        .init(symbol: "MES", name: "Micro E-mini S&P 500",      category: .microFuture,  tickSize: 0.25,    tickValue: 1.25, sortOrder: 40),
        .init(symbol: "YM",  name: "E-mini Dow",                category: .future,       tickSize: 1.00,    tickValue: 5.00, sortOrder: 50),
        .init(symbol: "MYM", name: "Micro E-mini Dow",          category: .microFuture,  tickSize: 1.00,    tickValue: 0.50, sortOrder: 60),
        .init(symbol: "RTY", name: "E-mini Russell 2000",       category: .future,       tickSize: 0.10,    tickValue: 5.00, sortOrder: 70),
        .init(symbol: "M2K", name: "Micro E-mini Russell 2000", category: .microFuture,  tickSize: 0.10,    tickValue: 0.50, sortOrder: 80),

        // Metals & energy (COMEX / NYMEX)
        .init(symbol: "GC",  name: "Gold Futures",              category: .future,       tickSize: 0.10,    tickValue: 10.00, sortOrder: 100),
        .init(symbol: "MGC", name: "Micro Gold Futures",        category: .microFuture,  tickSize: 0.10,    tickValue: 1.00,  sortOrder: 110),
        .init(symbol: "SI",  name: "Silver Futures",            category: .future,       tickSize: 0.005,   tickValue: 25.00, sortOrder: 120),
        .init(symbol: "CL",  name: "Crude Oil Futures",         category: .future,       tickSize: 0.01,    tickValue: 10.00, sortOrder: 130),
        .init(symbol: "MCL", name: "Micro Crude Oil Futures",   category: .microFuture,  tickSize: 0.01,    tickValue: 1.00,  sortOrder: 140),
        .init(symbol: "NG",  name: "Natural Gas Futures",       category: .future,       tickSize: 0.001,   tickValue: 10.00, sortOrder: 150),

        // Forex-majors (waarden per 1 standard lot van 100.000 units).
        // - 4-decimal paren: tickSize = 0.00001 (0.1 pip), tickValue = $1/lot per tick.
        //   Eén hele pip = 0.0001 → $10/lot; 100 pips → $1000/lot.
        // - JPY-paren (2-decimal, tick 0.001): tickValue afhankelijk van USDJPY-koers,
        //   default ≈ $0.67/lot per tick (grofweg equivalent aan $1/tick voor 4-dec paren).
        // `defaultQuantity` = 1 lot (niet 100.000 units).
        .init(symbol: "EURUSD", name: "Euro / US Dollar",             category: .forex, tickSize: 0.00001, tickValue: 1.00, currency: "USD", sortOrder: 200),
        .init(symbol: "GBPUSD", name: "British Pound / USD",          category: .forex, tickSize: 0.00001, tickValue: 1.00, currency: "USD", sortOrder: 210),
        .init(symbol: "AUDUSD", name: "Australian Dollar / USD",      category: .forex, tickSize: 0.00001, tickValue: 1.00, currency: "USD", sortOrder: 220),
        .init(symbol: "NZDUSD", name: "New Zealand Dollar / USD",     category: .forex, tickSize: 0.00001, tickValue: 1.00, currency: "USD", sortOrder: 230),
        .init(symbol: "USDCAD", name: "US Dollar / Canadian Dollar",  category: .forex, tickSize: 0.00001, tickValue: 0.75, currency: "USD", sortOrder: 240),
        .init(symbol: "USDCHF", name: "US Dollar / Swiss Franc",      category: .forex, tickSize: 0.00001, tickValue: 1.15, currency: "USD", sortOrder: 250),
        .init(symbol: "USDJPY", name: "US Dollar / Japanese Yen",     category: .forex, tickSize: 0.001,   tickValue: 0.67, currency: "USD", sortOrder: 260),
        .init(symbol: "EURJPY", name: "Euro / Japanese Yen",          category: .forex, tickSize: 0.001,   tickValue: 0.67, currency: "USD", sortOrder: 270),
        .init(symbol: "GBPJPY", name: "British Pound / Japanese Yen", category: .forex, tickSize: 0.001,   tickValue: 0.67, currency: "USD", sortOrder: 280)
    ]

    /// Snelle lookup op symbool (case-insensitive).
    public static func definition(for symbol: String) -> Definition? {
        let key = symbol.uppercased()
        return all.first { $0.symbol == key }
    }

    /// Instantieert de presets als `Instrument`-modellen zonder ze in te voegen.
    /// De caller besluit zelf hoe ze in de `ModelContext` opgenomen worden.
    public static func makeInstruments() -> [Instrument] {
        all.map { def in
            Instrument(
                name: def.name,
                symbol: def.symbol,
                category: def.category,
                tickSize: def.tickSize,
                tickValue: def.tickValue,
                currency: def.currency,
                defaultQuantity: def.defaultQuantity,
                isBuiltIn: true,
                sortOrder: def.sortOrder
            )
        }
    }
}
