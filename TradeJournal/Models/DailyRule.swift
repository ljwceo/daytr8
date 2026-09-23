import Foundation
import SwiftData

/// Een dagelijkse regel voor de progress tracker (bijv. "max 3 trades",
/// "stop na 2 verliezen", "journal ingevuld").
///
/// Automatische regels worden per dag beoordeeld door
/// `ProgressTrackerService`; handmatige regels worden afgevinkt via een
/// `DailyRuleCheck` per dag.
@Model
public final class DailyRule {

    public var id: UUID = UUID()
    public var name: String = ""

    /// Ruwe waarde van `DailyRuleKind`. Gebruik `kind` in code.
    public var kindRaw: String = DailyRuleKind.manual.rawValue

    /// Grenswaarde voor automatische regels (aantal trades, aantal verliezen
    /// of maximaal verlies in $). Genegeerd voor `manual`/`journalFilled`.
    public var threshold: Double = 0

    /// Inactieve regels tellen niet mee en worden niet getoond in de checklist.
    public var isActive: Bool = true

    public var sortOrder: Int = 0

    /// Dagen vóór de aanmaakdatum worden niet op deze regel beoordeeld, zodat
    /// een nieuwe regel de historische consistentie niet met terugwerkende
    /// kracht verlaagt.
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \DailyRuleCheck.rule)
    public var checks: [DailyRuleCheck] = []

    public init(
        id: UUID = UUID(),
        name: String,
        kind: DailyRuleKind,
        threshold: Double = 0,
        isActive: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.threshold = threshold
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    public var kind: DailyRuleKind {
        get { DailyRuleKind(rawValue: kindRaw) ?? .manual }
        set { kindRaw = newValue.rawValue }
    }
}

/// Afvinkstatus van een handmatige `DailyRule` op één dag.
@Model
public final class DailyRuleCheck {

    public var id: UUID = UUID()

    /// Dag (middernacht in de gebruikers-tijdzone).
    public var date: Date = Date()

    public var isFollowed: Bool = true

    public var rule: DailyRule?

    public init(id: UUID = UUID(), date: Date, isFollowed: Bool = true) {
        self.id = id
        self.date = date
        self.isFollowed = isFollowed
    }
}
