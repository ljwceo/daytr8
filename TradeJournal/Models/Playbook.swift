import Foundation
import SwiftData

/// Een playbook / strategie met bijbehorende regels en standaardconfluences.
@Model
public final class Playbook {

    public var id: UUID = UUID()
    public var name: String = ""
    public var descriptionText: String = ""
    public var iconName: String = "book"
    public var colorHex: String = "#4C8BF5"
    public var isArchived: Bool = false
    public var createdAt: Date = Date()

    /// Regels van dit playbook — worden per trade afgevinkt.
    @Relationship(deleteRule: .cascade, inverse: \PlaybookRule.playbook)
    public var rules: [PlaybookRule] = []

    /// Standaardconfluences die het formulier automatisch voorstelt.
    @Relationship
    public var defaultConfluences: [Confluence] = []

    /// Alle trades die dit playbook gebruiken.
    @Relationship(inverse: \Trade.playbook)
    public var trades: [Trade] = []

    public init(
        id: UUID = UUID(),
        name: String,
        descriptionText: String = "",
        iconName: String = "book",
        colorHex: String = "#4C8BF5",
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.iconName = iconName
        self.colorHex = colorHex
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

/// Regel binnen een playbook (bijv. "Wacht op sweep + IFVG in de killzone").
@Model
public final class PlaybookRule {

    public var id: UUID = UUID()
    public var text: String = ""
    public var sortOrder: Int = 0

    public var playbook: Playbook?

    /// Per trade wordt bijgehouden of deze regel wél of niet gevolgd is.
    @Relationship(deleteRule: .cascade, inverse: \PlaybookRuleAdherence.rule)
    public var adherences: [PlaybookRuleAdherence] = []

    public init(
        id: UUID = UUID(),
        text: String,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.text = text
        self.sortOrder = sortOrder
    }
}

/// Koppeling die per trade + regel bijhoudt of de regel gevolgd is.
/// Wordt gebruikt voor de "regels-gevolgd" statistiek in de trading score.
@Model
public final class PlaybookRuleAdherence {

    public var id: UUID = UUID()
    public var followed: Bool = false

    public var rule: PlaybookRule?
    public var trade: Trade?

    public init(
        id: UUID = UUID(),
        followed: Bool
    ) {
        self.id = id
        self.followed = followed
    }
}
