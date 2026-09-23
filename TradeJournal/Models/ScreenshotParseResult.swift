import Foundation

/// Eén door de screenshot-parser gevonden veld: de voorgestelde waarde, de
/// alternatieven (andere treffers op dezelfde screenshot) en waar hij vandaan komt.
public struct ParsedField<Value: Equatable>: Equatable {
    public var value: Value
    public var alternatives: [Value]
    /// Naam van het template dat de waarde vond (bijv. "Tradovate", "Generiek").
    public var source: String
    /// `true` als de waarde niet letterlijk op de screenshot stond maar is
    /// afgeleid (bijv. richting uit koop-/verkooptijd).
    public var isDerived: Bool

    public init(value: Value, alternatives: [Value] = [], source: String, isDerived: Bool = false) {
        self.value = value
        self.alternatives = alternatives
        self.source = source
        self.isDerived = isDerived
    }

    /// Voorgestelde waarde gevolgd door de alternatieven.
    public var candidates: [Value] { [value] + alternatives }
}

extension ParsedField: Sendable where Value: Sendable {}

/// Resultaat van `ScreenshotParser.parse(_:)`: alle herkende tradevelden.
/// Velden die niet gevonden zijn blijven `nil`.
public struct ScreenshotParseResult: Equatable, Sendable {
    /// `id` van het herkende platform-template; `nil` = onbekende layout
    /// (alleen generieke herkenning).
    public var templateID: String?
    public var templateName: String?

    public var symbol: ParsedField<String>?
    public var direction: ParsedField<TradeDirection>?
    public var entryPrice: ParsedField<Double>?
    public var exitPrice: ParsedField<Double>?
    public var stopLoss: ParsedField<Double>?
    public var takeProfit: ParsedField<Double>?
    public var quantity: ParsedField<Double>?
    public var grossPnL: ParsedField<Double>?
    public var netPnL: ParsedField<Double>?
    public var commission: ParsedField<Double>?
    public var fees: ParsedField<Double>?
    public var entryTime: ParsedField<Date>?
    public var exitTime: ParsedField<Date>?

    /// Tabel met meerdere trades (bijv. Tradovate Performance): elke rij als
    /// eigen resultaat, de eerste is ook het resultaat zelf. Leeg bij één
    /// trade of een label-waarde-layout.
    public var tableRows: [ScreenshotParseResult] = []

    public init(templateID: String? = nil, templateName: String? = nil) {
        self.templateID = templateID
        self.templateName = templateName
    }

    /// Velden die gevonden zijn, in vaste volgorde.
    public var recognizedFields: [ScreenshotField] {
        var fields: [ScreenshotField] = []
        if symbol != nil { fields.append(.symbol) }
        if direction != nil { fields.append(.direction) }
        if entryPrice != nil { fields.append(.entryPrice) }
        if exitPrice != nil { fields.append(.exitPrice) }
        if stopLoss != nil { fields.append(.stopLoss) }
        if takeProfit != nil { fields.append(.takeProfit) }
        if quantity != nil { fields.append(.quantity) }
        if grossPnL != nil { fields.append(.grossPnL) }
        if netPnL != nil { fields.append(.netPnL) }
        if commission != nil { fields.append(.commission) }
        if fees != nil { fields.append(.fees) }
        if entryTime != nil { fields.append(.entryTime) }
        if exitTime != nil { fields.append(.exitTime) }
        return fields
    }

    /// Niets bruikbaars gevonden.
    public var isEmpty: Bool { recognizedFields.isEmpty }
}
