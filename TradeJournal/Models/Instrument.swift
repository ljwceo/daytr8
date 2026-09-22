import Foundation
import SwiftData

/// Een verhandeld instrument (future, forex-paar, aandeel, ...).
///
/// Bewaart de eigenschappen die nodig zijn om P&L en R-multiples te berekenen:
/// - `tickSize`: de kleinste prijsbeweging (bijv. 0.25 voor NQ, 0.00001 voor EURUSD).
/// - `tickValue`: de dollarwaarde van één tick per contract/lot.
///
/// De ingebouwde presets worden op de eerste app-start ingeschoten via `InstrumentPresets`.
/// Gebruikers kunnen instrumenten bewerken en zelf toevoegen (zie `isBuiltIn`).
@Model
public final class Instrument {

    /// Stabiele identifier.
    public var id: UUID = UUID()

    /// Weergavenaam (bijv. "E-mini Nasdaq-100").
    public var name: String = ""

    /// Symbool zoals gebruikt door de broker (bijv. "NQ", "EURUSD").
    public var symbol: String = ""

    /// Ruwe waarde van `InstrumentCategory`.
    public var categoryRaw: String = InstrumentCategory.other.rawValue

    /// Kleinste prijsbeweging.
    public var tickSize: Double = 0.01

    /// Dollarwaarde van één tick per contract/lot.
    public var tickValue: Double = 1

    /// ISO 4217-code — meestal USD voor futures, EUR/GBP/JPY voor forex.
    public var currency: String = "USD"

    /// Standaard aantal contracten dat het formulier voorstelt.
    public var defaultQuantity: Double = 1

    /// Meegeleverd door de app (niet te verwijderen, maar wel bewerkbaar).
    public var isBuiltIn: Bool = false

    /// Sortering in kiezers; lager = eerder.
    public var sortOrder: Int = 0

    /// Aanmaakmoment.
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        category: InstrumentCategory,
        tickSize: Double,
        tickValue: Double,
        currency: String = "USD",
        defaultQuantity: Double = 1,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.categoryRaw = category.rawValue
        self.tickSize = tickSize
        self.tickValue = tickValue
        self.currency = currency
        self.defaultQuantity = defaultQuantity
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    public var category: InstrumentCategory {
        get { InstrumentCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Dollarwaarde van één prijs-punt per contract (tickValue / tickSize).
    public var pointValue: Double {
        guard tickSize > 0 else { return 0 }
        return tickValue / tickSize
    }
}
