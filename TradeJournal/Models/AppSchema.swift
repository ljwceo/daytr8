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
