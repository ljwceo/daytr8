import Foundation
import SwiftData

/// Lokaal opgeslagen screenshot bij een trade.
///
/// De afbeeldingsbytes worden externally opgeslagen om de SQLite-database klein
/// te houden. Zowel foto's uit de bibliotheek als camera-opnames komen hier terecht.
@Model
public final class TradeScreenshot {

    public var id: UUID = UUID()

    /// Ruwe bytes van de afbeelding (JPEG/PNG). Wordt externally opgeslagen.
    @Attribute(.externalStorage)
    public var imageData: Data = Data()

    /// Optionele onderschrift ("15m entry", "1H context", ...).
    public var caption: String = ""

    /// Volgorde binnen de trade (lager = eerder).
    public var sortOrder: Int = 0

    /// Aanmaakmoment.
    public var createdAt: Date = Date()

    /// Bovenliggende trade — de inverse-kant staat op `Trade.screenshots`.
    public var trade: Trade?

    public init(
        id: UUID = UUID(),
        imageData: Data,
        caption: String = "",
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.imageData = imageData
        self.caption = caption
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
