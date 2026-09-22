import Foundation
import SwiftData

/// Losse fill (executie) van een trade.
///
/// Een `Trade` kan één of meerdere `TradeExecution`s hebben. De eerste executies
/// bouwen de positie op, latere sluiten hem (partial exits). De volgorde is
/// bepaald door `date`.
///
/// De volgende conventie geldt: `signedQuantity > 0` is een koop-executie, `< 0`
/// een verkoop-executie. Voor een long trade opent een koop en sluit een verkoop
/// de positie; voor een short trade omgekeerd. De helpers `entryQuantity`/
/// `exitQuantity` verbergen dit voor de UI en berekeningen.
@Model
public final class TradeExecution {

    public var id: UUID = UUID()

    /// Tijdstip van de fill.
    public var date: Date = Date()

    /// Uitvoeringsprijs.
    public var price: Double = 0

    /// Aantal contracten / lots, mét teken:
    /// - positief = koop
    /// - negatief = verkoop
    public var signedQuantity: Double = 0

    /// Commissie in accountvaluta voor déze fill.
    public var commission: Double = 0

    /// Extra kosten (exchange fees etc.) in accountvaluta voor déze fill.
    public var fees: Double = 0

    /// Optionele notitie ("BE stop hit", "TP1 hit", ...).
    public var note: String = ""

    /// Bovenliggende trade — de inverse-kant staat op `Trade.executions`.
    public var trade: Trade?

    public init(
        id: UUID = UUID(),
        date: Date,
        price: Double,
        signedQuantity: Double,
        commission: Double = 0,
        fees: Double = 0,
        note: String = ""
    ) {
        self.id = id
        self.date = date
        self.price = price
        self.signedQuantity = signedQuantity
        self.commission = commission
        self.fees = fees
        self.note = note
    }

    /// Absolute grootte van de fill.
    public var quantity: Double { abs(signedQuantity) }

    /// True als deze fill de positie vergroot voor de gegeven richting.
    public func isEntry(for direction: TradeDirection) -> Bool {
        switch direction {
        case .long: return signedQuantity > 0
        case .short: return signedQuantity < 0
        }
    }

    /// True als deze fill de positie verkleint voor de gegeven richting.
    public func isExit(for direction: TradeDirection) -> Bool {
        switch direction {
        case .long: return signedQuantity < 0
        case .short: return signedQuantity > 0
        }
    }
}
