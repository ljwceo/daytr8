import Foundation
import SwiftData

/// Één centrale plek waar het SwiftData-schema samenkomt. Zowel `TradeJournalApp`
/// als de unit tests bouwen hun `ModelContainer` op basis van deze lijst.
public enum AppSchema {

    /// Alle @Model-types van de huidige schemaversie (`AppSchemaV2`).
    public static let models: [any PersistentModel.Type] = v1Models + [
        // Aanpasbaar dashboard: dashboards (tabbladen) met widgets.
        Dashboard.self,
        DashboardWidget.self,
        // Markering "snel toegevoegd" van trades uit de MT5-screenshotimport.
        TradeImportMark.self
    ]

    /// De modellen van schemaversie 1, bevroren. Niet meer aanpassen: een
    /// bestaande store wordt aan precies deze lijst herkend.
    public static let v1Models: [any PersistentModel.Type] = [
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

/// Versie 1 van het SwiftData-schema: de modellen tot en met de release vóór
/// het aanpasbare dashboard (`AppSchema.v1Models`).
///
/// Een bestaande (nog ongeversioneerde) store heeft dezelfde modelhash en
/// wordt daardoor zonder omzetting als V1 herkend.
public enum AppSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { AppSchema.v1Models }
}

/// Versie 2: V1 plus `Dashboard`, `DashboardWidget` en `TradeImportMark`.
///
/// Alleen nieuwe entiteiten; geen bestaand model is gewijzigd. Daardoor is
/// de stap V1 → V2 een lichtgewicht migratie: alle bestaande data blijft
/// staan en de nieuwe tabellen beginnen leeg (de standaardindeling van het
/// dashboard komt daarna via `SeedService`).
///
/// Wijzigt een model later op een manier die SwiftData niet zelf kan
/// migreren, voeg dan een `AppSchemaV3` toe (met de oude modeltypes genest)
/// en een `MigrationStage.custom` in `AppMigrationPlan.stages`.
public enum AppSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    public static var models: [any PersistentModel.Type] { AppSchema.models }
}

/// Migratieplan van de store: alle schemaversies (oud → nieuw) en de stappen
/// ertussen. `PersistenceController` opent de container altijd met dit plan.
public enum AppMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self, AppSchemaV2.self] }
    public static var stages: [MigrationStage] {
        [
            // V1 → V2: alleen nieuwe entiteiten, dus lichtgewicht.
            MigrationStage.lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self)
        ]
    }
}
