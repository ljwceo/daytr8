import Foundation
import SwiftData

/// Beheer en toepassing van daily journal-templates (SPEC §10).
///
/// - `defaults`: de standaard pre-market- en post-market-templates die
///   `SeedService` bij de eerste start inschiet.
/// - `render`/`apply`: template-tekst invullen (placeholder `{{datum}}`) en in
///   een bestaand journalveld zetten zonder bestaande tekst te overschrijven.
/// - `create`/`update`/`setDefault`/`delete`: bewerkingen voor het
///   instellingenscherm, zodat views zelf geen `ModelContext` muteren.
public struct JournalTemplateService {

    /// Een standaardtemplate zoals meegeleverd met de app.
    public struct Definition: Equatable, Sendable {
        public let kind: JournalTemplateKind
        public let name: String
        public let body: String
    }

    /// Wordt bij het toepassen vervangen door de datum van de handelsdag.
    public static let datePlaceholder = "{{datum}}"

    public static let defaults: [Definition] = [
        Definition(
            kind: .preMarket,
            name: "Pre-market plan",
            body: """
            Pre-market — {{datum}}

            HTF bias (weekly / daily):
            Belangrijke levels (PDH/PDL, Asia/London high/low):
            Liquiditeit waar ik op let:
            Nieuws & events (tijd + impact):
            A+ setup vandaag:
            Max risk vandaag:
            Mentale staat (1–10):
            """
        ),
        Definition(
            kind: .postMarket,
            name: "Post-market review",
            body: """
            Post-market review — {{datum}}

            Wat ging goed:
            Wat ging fout:
            Heb ik mijn plan en regels gevolgd?
            Beste trade en waarom:
            Les voor morgen:
            """
        )
    ]

    public init() {}

    // MARK: - Toepassen

    /// Vervangt `{{datum}}` door de volledige Nederlandse datum van `date`
    /// (bijv. "maandag 22 september 2026").
    public func render(_ body: String, for date: Date, timeZone: TimeZone = .current) -> String {
        guard body.contains(Self.datePlaceholder) else { return body }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return body.replacingOccurrences(of: Self.datePlaceholder, with: formatter.string(from: date))
    }

    /// Zet de (ingevulde) template in een journalveld:
    /// - leeg veld → alleen de template;
    /// - veld bevat de template al → ongewijzigd (geen dubbele invoeging);
    /// - anders → bestaande tekst, een lege regel, dan de template.
    public func apply(_ body: String, to existing: String, date: Date, timeZone: TimeZone = .current) -> String {
        let rendered = render(body, for: date, timeZone: timeZone)
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return rendered }
        if existing.contains(rendered) { return existing }
        return trimmed + "\n\n" + rendered
    }

    /// De standaardtemplate van een soort: de template met `isDefault`, anders
    /// de eerste op `sortOrder`.
    public func defaultTemplate(for kind: JournalTemplateKind, in templates: [JournalTemplate]) -> JournalTemplate? {
        let ofKind = sorted(templates.filter { $0.kind == kind })
        return ofKind.first(where: \.isDefault) ?? ofKind.first
    }

    /// Templates van één soort, standaard eerst, daarna op `sortOrder`/naam.
    public func sorted(_ templates: [JournalTemplate]) -> [JournalTemplate] {
        templates.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Bewerken

    /// Maakt een nieuwe template. De eerste template van een soort wordt
    /// automatisch de standaard.
    @discardableResult
    public func create(kind: JournalTemplateKind, name: String, body: String, in context: ModelContext) -> JournalTemplate {
        let existing = templates(of: kind, in: context)
        let template = JournalTemplate(
            kind: kind,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body,
            isDefault: existing.isEmpty,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(template)
        return template
    }

    public func update(_ template: JournalTemplate, name: String, body: String, now: Date = Date()) {
        template.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        template.body = body
        template.updatedAt = now
    }

    /// Maakt `template` de standaard van zijn soort (en haalt de vlag bij de
    /// andere templates van die soort weg).
    public func setDefault(_ template: JournalTemplate, in context: ModelContext) {
        for other in templates(of: template.kind, in: context) {
            other.isDefault = other.id == template.id
        }
    }

    /// Verwijdert een template. Was het de standaard, dan wordt de volgende
    /// template van dezelfde soort de nieuwe standaard.
    public func delete(_ template: JournalTemplate, in context: ModelContext) {
        let kind = template.kind
        let wasDefault = template.isDefault
        let templateID = template.id
        context.delete(template)
        guard wasDefault else { return }
        let remaining = sorted(templates(of: kind, in: context).filter { $0.id != templateID })
        remaining.first?.isDefault = true
    }

    private func templates(of kind: JournalTemplateKind, in context: ModelContext) -> [JournalTemplate] {
        let all = (try? context.fetch(FetchDescriptor<JournalTemplate>())) ?? []
        return all.filter { $0.kind == kind }
    }
}
