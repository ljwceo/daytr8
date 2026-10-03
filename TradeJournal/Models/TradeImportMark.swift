import Foundation
import SwiftData

/// Herkomst van een snel toegevoegde trade.
public enum TradeImportSource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Bulk-import vanaf screenshots van de MetaTrader 5-geschiedenis.
    case mt5Screenshot = "mt5_screenshot"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mt5Screenshot: return "MT5-screenshot"
        }
    }
}

/// Markering "snel toegevoegd" op een trade: de trade is met alleen de harde
/// cijfers geïmporteerd en kan later aangevuld worden (confluences, playbook,
/// notities).
///
/// Bewust een apart model met alleen het trade-id (geen relatie): zo blijft
/// `Trade` ongewijzigd en is schemaversie 2 een lichtgewicht migratie. De
/// markering verdwijnt mee met de trade (`TradeEditingService.delete`) of
/// zodra de gebruiker hem weghaalt.
@Model
public final class TradeImportMark {

    public var id: UUID = UUID()

    /// `Trade.id` van de gemarkeerde trade.
    public var tradeID: UUID = UUID()

    /// Ruwe waarde van `TradeImportSource`.
    public var sourceRaw: String = TradeImportSource.mt5Screenshot.rawValue

    public var importedAt: Date = Date()

    public init(id: UUID = UUID(), tradeID: UUID, source: TradeImportSource = .mt5Screenshot, importedAt: Date = Date()) {
        self.id = id
        self.tradeID = tradeID
        self.sourceRaw = source.rawValue
        self.importedAt = importedAt
    }

    public var source: TradeImportSource {
        get { TradeImportSource(rawValue: sourceRaw) ?? .mt5Screenshot }
        set { sourceRaw = newValue.rawValue }
    }
}
