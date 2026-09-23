import Foundation
import SwiftData

/// Beheer van confluences (Meer → Confluences): eigen confluences toevoegen,
/// bestaande bewerken, archiveren, sorteren en verwijderen, en de
/// standaardset terugzetten.
@Observable
public final class ConfluenceSettingsViewModel {

    /// Invoer van de editor-sheet.
    public struct Draft: Equatable {
        public var name: String = ""
        public var category: ConfluenceCategory = .other
        public var colorHex: String = ConfluenceCategory.other.defaultColorHex
        public var iconName: String = "tag"
        public var descriptionText: String = ""
        public var isActive: Bool = true

        public init(category: ConfluenceCategory = .other) {
            self.category = category
            self.colorHex = category.defaultColorHex
        }

        public init(from confluence: Confluence) {
            name = confluence.name
            category = confluence.category
            colorHex = confluence.colorHex
            iconName = confluence.iconName
            descriptionText = confluence.descriptionText
            isActive = confluence.isActive
        }

        public var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Kleuren waaruit in de editor gekozen kan worden (hex, zoals opgeslagen
    /// op `Confluence.colorHex`): eerst de categoriekleuren, dan extra's.
    public static let colorOptions: [String] = ConfluenceCategory.allCases.map(\.defaultColorHex) + [
        "#F2C94C", "#56CCF2", "#EB5CA8", "#6FCF97", "#BB6BD9", "#F2994A"
    ]

    /// SF Symbols waaruit in de editor gekozen kan worden.
    public static let iconOptions: [String] = [
        "tag", "star", "flag", "bolt", "target", "scope", "sparkles", "flame",
        "arrow.up.right", "arrow.down.right", "arrow.up.to.line", "arrow.down.to.line",
        "arrow.turn.up.right", "arrow.triangle.swap", "arrow.left.arrow.right", "equal.circle",
        "rectangle.split.3x1", "square.stack.3d.up", "square.stack", "hammer",
        "waveform.path.ecg", "chart.line.uptrend.xyaxis", "chart.xyaxis.line", "ruler",
        "clock", "clock.badge", "hourglass", "calendar", "sun.max", "moon", "newspaper", "hand.raised"
    ]

    public init() {}

    /// Fout bij de naam, of `nil` als hij geldig is. Namen zijn uniek
    /// (hoofdletterongevoelig) — dubbele namen zijn in rapporten niet te onderscheiden.
    public func nameError(for draft: Draft, existing: Confluence?, all: [Confluence]) -> String? {
        let name = draft.trimmedName
        if name.isEmpty { return "Vul een naam in." }
        let duplicate = all.contains { $0 !== existing && $0.name.lowercased() == name.lowercased() }
        return duplicate ? "Er bestaat al een confluence met deze naam." : nil
    }

    @discardableResult
    public func save(_ draft: Draft, existing: Confluence?, all: [Confluence], in context: ModelContext) -> Confluence? {
        guard nameError(for: draft, existing: existing, all: all) == nil else { return nil }
        let confluence: Confluence
        if let existing {
            confluence = existing
            if existing.category != draft.category {
                confluence.sortOrder = nextSortOrder(in: draft.category, all: all)
            }
        } else {
            confluence = Confluence(name: draft.trimmedName, category: draft.category, sortOrder: nextSortOrder(in: draft.category, all: all))
            context.insert(confluence)
        }
        confluence.name = draft.trimmedName
        confluence.category = draft.category
        confluence.colorHex = draft.colorHex
        confluence.iconName = draft.iconName
        confluence.descriptionText = draft.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        confluence.isActive = draft.isActive
        return confluence
    }

    /// Archiveren (of terugzetten): verdwijnt uit nieuwe trades, bestaande
    /// trades en rapporten houden hem.
    public func setActive(_ confluence: Confluence, _ isActive: Bool) {
        confluence.isActive = isActive
    }

    /// Verwijdert de confluence definitief; trades en playbooks verliezen de koppeling.
    public func delete(_ confluence: Confluence, in context: ModelContext) {
        context.delete(confluence)
    }

    /// Nieuwe volgorde na slepen binnen één categorie (`items` = die categorie,
    /// gesorteerd zoals getoond).
    public func move(_ items: [Confluence], from source: IndexSet, to destination: Int) {
        guard !items.isEmpty else { return }
        let base = items.map(\.sortOrder).min() ?? 0
        let moving = source.sorted().map { items[$0] }
        var ordered = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertionIndex = min(max(destination - source.filter { $0 < destination }.count, 0), ordered.count)
        ordered.insert(contentsOf: moving, at: insertionIndex)
        for (index, confluence) in ordered.enumerated() {
            confluence.sortOrder = base + index
        }
    }

    /// Zet verwijderde standaardconfluences terug. Geeft het aantal terug.
    @discardableResult
    public func restoreDefaults(in context: ModelContext) -> Int {
        SeedService.restoreDefaultConfluences(in: context)
    }

    private func nextSortOrder(in category: ConfluenceCategory, all: [Confluence]) -> Int {
        let orders = all.filter { $0.category == category }.map(\.sortOrder)
        if let max = orders.max() { return max + 1 }
        // Lege categorie: achter de laatste confluence van eerdere categorieën.
        return (all.map(\.sortOrder).max() ?? 0) + 1
    }
}
