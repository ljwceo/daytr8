import Foundation
import SwiftData

/// Verantwoordelijk voor het idempotent inschieten van standaard-data
/// (instrumentpresets en de standaard confluence-set) op de eerste start
/// van de app.
///
/// De service is bewust puur werkend met een `ModelContext`, zodat hij
/// vanuit `TradeJournalApp.init` én vanuit unit tests aangeroepen kan worden.
///
/// Callers zijn zelf verantwoordelijk om vanuit de juiste thread te werken;
/// de main-context van een `ModelContainer` hoort op de main thread aangeroepen te worden.
public enum SeedService {

    /// Voert alle idempotente seeds uit. Veilig om bij elke app-start
    /// te draaien: bestaande entries worden herkend aan hun `symbol`/`name`
    /// in combinatie met `isBuiltIn`.
    public static func seedDefaultsIfNeeded(in context: ModelContext) {
        seedInstrumentPresetsIfNeeded(in: context)
        seedConfluencesIfNeeded(in: context)

        do {
            try context.save()
        } catch {
            // Bewust geen crash: als save faalt, laten we het aan de app over
            // om er in latere fases op te reageren.
            #if DEBUG
            print("SeedService.save error: \(error)")
            #endif
        }
    }

    // MARK: - Presets

    public static func seedInstrumentPresetsIfNeeded(in context: ModelContext) {
        let existingSymbols: Set<String> = (fetchAll(Instrument.self, in: context)).reduce(into: []) { acc, inst in
            acc.insert(inst.symbol.uppercased())
        }

        for def in InstrumentPresets.all where !existingSymbols.contains(def.symbol.uppercased()) {
            let inst = Instrument(
                name: def.name,
                symbol: def.symbol,
                category: def.category,
                tickSize: def.tickSize,
                tickValue: def.tickValue,
                currency: def.currency,
                defaultQuantity: def.defaultQuantity,
                isBuiltIn: true,
                sortOrder: def.sortOrder
            )
            context.insert(inst)
        }
    }

    // MARK: - Confluences

    public static func seedConfluencesIfNeeded(in context: ModelContext) {
        let existing = fetchAll(Confluence.self, in: context)
        // Bestaande confluences herkennen we op naam (case-insensitive) — zo
        // duplicieren we niet als de gebruiker eerder handmatig een met dezelfde
        // naam heeft aangemaakt.
        let existingNames: Set<String> = existing.reduce(into: []) { $0.insert($1.name.lowercased()) }

        for def in DefaultConfluences.all where !existingNames.contains(def.name.lowercased()) {
            let conf = Confluence(
                name: def.name,
                category: def.category,
                iconName: def.icon,
                isActive: true,
                isBuiltIn: true,
                sortOrder: def.sortOrder
            )
            context.insert(conf)
        }
    }

    // MARK: - Helper

    private static func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        do {
            return try context.fetch(FetchDescriptor<T>())
        } catch {
            return []
        }
    }
}
