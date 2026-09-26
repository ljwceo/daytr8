import Foundation
import SwiftData

/// Één centrale plek waar het SwiftData-schema samenkomt. Zowel `TradeJournalApp`
/// als de unit tests bouwen hun `ModelContainer` op basis van deze lijst.
public enum AppSchema {

    /// Alle @Model-types van de app, in de volgorde waarin ze in SPEC.md staan.
    public static let models: [any PersistentModel.Type] = [
        Account.self,
        Instrument.self,
        Trade.self,
        TradeExecution.self,
        TradeScreenshot.self,
        Confluence.self,
        Playbook.self,
        PlaybookRule.self,
        PlaybookRuleAdherence.self,
        DailyJournal.self,
        DailyJournalScreenshot.self,
        Tag.self,
        Mistake.self,
        // Fase 6: templates, progress tracker en notebook (SPEC §10).
        JournalTemplate.self,
        DailyRule.self,
        DailyRuleCheck.self,
        NotebookNote.self
    ]
}

/// Versie 1 van het SwiftData-schema: precies de modellen uit
/// `AppSchema.models` zoals ze tot en met deze release bestonden.
///
/// Een bestaande (nog ongeversioneerde) store heeft dezelfde modelhash en
/// wordt daardoor zonder omzetting als V1 herkend. Wijzigt een model later op
/// een manier die SwiftData niet zelf (lichtgewicht) kan migreren, voeg dan
/// een `AppSchemaV2` toe (met de oude modeltypes genest in V1) en een
/// `MigrationStage` in `AppMigrationPlan.stages` die de oude data omzet in
/// plaats van weggooit.
public enum AppSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { AppSchema.models }
}

/// Migratieplan van de store: alle schemaversies (oud → nieuw) en de stappen
/// ertussen. `PersistenceController` opent de container altijd met dit plan.
public enum AppMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
