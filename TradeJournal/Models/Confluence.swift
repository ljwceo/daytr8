import Foundation
import SwiftData

/// Een confluence die aan een trade gekoppeld kan worden (bijv. "IFVG", "Sweep PDL").
///
/// Confluences worden gegroepeerd per categorie (bias, PD arrays, liquiditeit, ...)
/// en in het tradeformulier als multi-select chips getoond.
/// Elke confluence komt in de rapportage terug (win rate, netto P&L per confluence).
@Model
public final class Confluence {

    public var id: UUID = UUID()

    /// Weergavenaam (bijv. "Sweep PDH").
    public var name: String = ""

    /// Ruwe waarde van `ConfluenceCategory`.
    public var categoryRaw: String = ConfluenceCategory.other.rawValue

    /// Kleur in hex-formaat (bijv. "#4C8BF5").
    public var colorHex: String = "#9AA0A6"

    /// SF Symbol-naam voor het chip-icoon.
    public var iconName: String = "tag"

    /// Wanneer `false` verschijnt de confluence niet meer in nieuwe trades,
    /// maar bestaande trades behouden hem.
    public var isActive: Bool = true

    /// Onderdeel van de meegeleverde standaardset.
    public var isBuiltIn: Bool = false

    /// Sortering binnen de categorie (lager = eerder).
    public var sortOrder: Int = 0

    /// Optionele beschrijving die in een popover uitgelegd kan worden.
    public var descriptionText: String = ""

    /// Alle trades waar deze confluence bij is aangevinkt (many-to-many).
    @Relationship(inverse: \Trade.confluences)
    public var trades: [Trade] = []

    /// Playbooks die deze confluence als standaard hebben.
    @Relationship(inverse: \Playbook.defaultConfluences)
    public var playbooks: [Playbook] = []

    public init(
        id: UUID = UUID(),
        name: String,
        category: ConfluenceCategory,
        colorHex: String? = nil,
        iconName: String = "tag",
        isActive: Bool = true,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0,
        descriptionText: String = ""
    ) {
        self.id = id
        self.name = name
        self.categoryRaw = category.rawValue
        self.colorHex = colorHex ?? category.defaultColorHex
        self.iconName = iconName
        self.isActive = isActive
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.descriptionText = descriptionText
    }

    public var category: ConfluenceCategory {
        get { ConfluenceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}
