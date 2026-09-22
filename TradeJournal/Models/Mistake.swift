import Foundation
import SwiftData

/// Een gecategoriseerde fout die aan een trade gekoppeld kan worden
/// (bijv. "Te vroeg entry", "Stop te wijd", "Geen playbook").
///
/// Wordt in de rapportage gebruikt om te zien hoeveel elke fout kost.
@Model
public final class Mistake {

    public var id: UUID = UUID()
    public var name: String = ""
    public var colorHex: String = "#E0554D"
    public var descriptionText: String = ""
    public var isBuiltIn: Bool = false
    public var createdAt: Date = Date()

    @Relationship(inverse: \Trade.mistakes)
    public var trades: [Trade] = []

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#E0554D",
        descriptionText: String = "",
        isBuiltIn: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.descriptionText = descriptionText
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }
}
