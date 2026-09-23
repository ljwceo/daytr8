import Foundation

/// Velden die de screenshot-import (SPEC.md §12) uit OCR-tekst kan halen.
///
/// De ruwe waarde is ook de sleutel in `fields` van een broker-template
/// (`Resources/ScreenshotTemplates/*.json`).
public enum ScreenshotField: String, Codable, CaseIterable, Identifiable, Sendable {
    case symbol
    case direction
    case entryPrice = "entry_price"
    case exitPrice = "exit_price"
    case stopLoss = "stop_loss"
    case takeProfit = "take_profit"
    case quantity
    case grossPnL = "gross_pnl"
    case netPnL = "net_pnl"
    case commission
    case fees
    case entryTime = "entry_time"
    case exitTime = "exit_time"
    /// Koop-/verkoopkant zoals sommige platforms (Tradovate) ze tonen in plaats
    /// van entry/exit. De parser zet ze om naar entry/exit + richting.
    case buyPrice = "buy_price"
    case sellPrice = "sell_price"
    case buyTime = "buy_time"
    case sellTime = "sell_time"

    public var id: String { rawValue }

    /// Soort waarde, bepaalt hoe de parser de gematchte tekst omzet.
    public enum ValueKind: Sendable {
        case symbol
        case direction
        case number
        case dateTime
    }

    public var valueKind: ValueKind {
        switch self {
        case .symbol: return .symbol
        case .direction: return .direction
        case .entryTime, .exitTime, .buyTime, .sellTime: return .dateTime
        default: return .number
        }
    }

    public var displayName: String {
        switch self {
        case .symbol: return "Symbool"
        case .direction: return "Richting"
        case .entryPrice: return "Entry-prijs"
        case .exitPrice: return "Exit-prijs"
        case .stopLoss: return "Stop loss"
        case .takeProfit: return "Take profit"
        case .quantity: return "Aantal"
        case .grossPnL: return "Bruto P&L"
        case .netPnL: return "Netto P&L"
        case .commission: return "Commissie"
        case .fees: return "Fees"
        case .entryTime: return "Entry-tijd"
        case .exitTime: return "Exit-tijd"
        case .buyPrice: return "Koopprijs"
        case .sellPrice: return "Verkoopprijs"
        case .buyTime: return "Kooptijd"
        case .sellTime: return "Verkooptijd"
        }
    }

    /// Velden die inhoudelijk bij elkaar horen. Definieert een broker-template
    /// één veld uit zo'n groep, dan vult de generieke terugval de andere velden
    /// uit die groep niet aan: het platform weet het beter (bijv. Tradovate
    /// toont bruto P&L; een generieke "P&L"-regex zou die als netto lezen).
    static let relatedGroups: [Set<ScreenshotField>] = [
        [.grossPnL, .netPnL],
        [.entryPrice, .exitPrice, .buyPrice, .sellPrice],
        [.entryTime, .exitTime, .buyTime, .sellTime],
        [.direction, .buyTime, .sellTime]
    ]

    /// Dit veld plus alle velden die er een groep mee delen.
    var relatedFields: Set<ScreenshotField> {
        Self.relatedGroups
            .filter { $0.contains(self) }
            .reduce(into: Set<ScreenshotField>([self])) { $0.formUnion($1) }
    }
}

/// Broker-template voor de screenshot-import, ingelezen uit JSON
/// (`Resources/ScreenshotTemplates/<id>.json`). Een nieuw platform toevoegen
/// = een nieuw JSON-bestand in die map, zonder Swift-code aan te passen.
///
/// Voorbeeld:
/// ```json
/// {
///   "formatVersion": 1,
///   "id": "tradovate",
///   "name": "Tradovate",
///   "priority": 10,
///   "keywords": ["tradovate", "bought timestamp"],
///   "dateOrder": "month_first",
///   "fields": {
///     "gross_pnl": { "patterns": ["\\bp\\s*&\\s*l\\s*[:=]?\\s*(-?[0-9.,]+)"] },
///     "commission": { "patterns": ["..."], "postProcess": ["absolute"] }
///   }
/// }
/// ```
///
/// - `keywords`: herkenningswoorden (hoofdletterongevoelig). Het template met
///   de meeste treffers wint; bij gelijkspel de hoogste `priority`.
/// - `isFallback`: generiek template (`default.json`) dat ontbrekende velden
///   aanvult en gebruikt wordt als geen platform herkend is.
/// - `fields`: per `ScreenshotField.rawValue` één of meer regexen
///   (hoofdletterongevoelig). De waarde is capture group `group`, of anders de
///   eerste niet-lege capture group. Alle treffers worden kandidaten; de eerste
///   is de voorgestelde waarde.
/// - `postProcess`: optionele stappen na het omzetten: `absolute`, `negate`
///   (getallen), `uppercase`, `strip_spaces` (tekst).
/// - `columns` (optioneel): tabelweergave met kolomkoppen op één regel en per
///   trade een rij eronder (bijv. Tradovate Performance, NinjaTrader Trades).
///   Per veld de mogelijke kopteksten (hoofdletterongevoelig, hele woorden).
///   Sleutels die geen veld zijn (bijv. `"other"`) zijn kolommen die de
///   parser herkent maar overslaat, zodat hun waarden niet bij een buurkolom
///   terechtkomen. Een rij met minstens drie herkende koppen is de kopregel.
///
///   ```json
///   "columns": {
///     "entry_price": { "labels": ["entry price"] },
///     "commission": { "labels": ["commission"], "postProcess": ["absolute"] },
///     "other": { "labels": ["account", "strategy"] }
///   }
///   ```
public struct ScreenshotTemplate: Codable, Identifiable, Equatable, Sendable {

    /// Hoogste templateformaat dat deze app-versie begrijpt.
    public static let supportedFormatVersion = 1

    public struct FieldRule: Codable, Equatable, Sendable {
        public var patterns: [String]
        /// Capture group met de waarde (1-based). `nil` = eerste niet-lege group.
        public var group: Int?
        public var postProcess: [String]?

        public init(patterns: [String], group: Int? = nil, postProcess: [String]? = nil) {
            self.patterns = patterns
            self.group = group
            self.postProcess = postProcess
        }
    }

    /// Kolom in een tabelweergave: de mogelijke kopteksten.
    public struct ColumnRule: Codable, Equatable, Sendable {
        public var labels: [String]
        public var postProcess: [String]?

        public init(labels: [String], postProcess: [String]? = nil) {
            self.labels = labels
            self.postProcess = postProcess
        }
    }

    public var formatVersion: Int
    public var id: String
    public var name: String
    public var isFallback: Bool?
    public var priority: Int?
    public var keywords: [String]
    /// Volgorde van dag/maand in datums als `09/10/2025`. Jaar-eerst is altijd eenduidig.
    public var dateOrder: ImportDateOrder?
    public var fields: [String: FieldRule]
    /// Tabelweergave (optioneel), zie de uitleg boven dit type.
    public var columns: [String: ColumnRule]?

    public init(
        formatVersion: Int = ScreenshotTemplate.supportedFormatVersion,
        id: String,
        name: String,
        isFallback: Bool? = nil,
        priority: Int? = nil,
        keywords: [String],
        dateOrder: ImportDateOrder? = nil,
        fields: [String: FieldRule],
        columns: [String: ColumnRule]? = nil
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.name = name
        self.isFallback = isFallback
        self.priority = priority
        self.keywords = keywords
        self.dateOrder = dateOrder
        self.fields = fields
        self.columns = columns
    }

    public var isFallbackTemplate: Bool { isFallback ?? false }

    public func rule(for field: ScreenshotField) -> FieldRule? {
        fields[field.rawValue]
    }

    /// Velden waarvoor dit template regexen heeft, in vaste volgorde.
    /// Onbekende sleutels in de JSON worden genegeerd.
    public var definedFields: [ScreenshotField] {
        ScreenshotField.allCases.filter { fields[$0.rawValue] != nil }
    }
}
