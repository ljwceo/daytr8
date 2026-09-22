import Foundation

/// Het JSON-document (`backup.json`) in een backup-zip.
///
/// Bevat alle SwiftData-entiteiten als platte DTO's; relaties worden via
/// `UUID`'s vastgelegd. Afbeeldingen staan als losse bestanden in de map
/// `images/` van de zip en worden hier alleen bij bestandsnaam genoemd.
///
/// `formatVersion` wordt bij elke incompatibele wijziging opgehoogd, zodat
/// `BackupService` oudere backups kan migreren en nieuwere kan weigeren.
public struct BackupPayload: Codable, Equatable {

    /// Huidige versie van het backup-formaat.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var appVersion: String

    public var accounts: [AccountDTO]
    public var instruments: [InstrumentDTO]
    public var confluences: [ConfluenceDTO]
    public var tags: [LabelDTO]
    public var mistakes: [MistakeDTO]
    public var playbooks: [PlaybookDTO]
    public var trades: [TradeDTO]
    public var dailyJournals: [DailyJournalDTO]

    // MARK: - DTO's

    public struct AccountDTO: Codable, Equatable {
        public var id: UUID
        public var name: String
        public var type: String
        public var startingBalance: Double
        public var broker: String
        public var currency: String
        public var maxDrawdown: Double?
        public var dailyLossLimit: Double?
        public var monthlyProfitTarget: Double?
        public var createdAt: Date
        public var isArchived: Bool
    }

    public struct InstrumentDTO: Codable, Equatable {
        public var id: UUID
        public var name: String
        public var symbol: String
        public var category: String
        public var tickSize: Double
        public var tickValue: Double
        public var currency: String
        public var defaultQuantity: Double
        public var isBuiltIn: Bool
        public var sortOrder: Int
        public var createdAt: Date
    }

    public struct ConfluenceDTO: Codable, Equatable {
        public var id: UUID
        public var name: String
        public var category: String
        public var colorHex: String
        public var iconName: String
        public var isActive: Bool
        public var isBuiltIn: Bool
        public var sortOrder: Int
        public var descriptionText: String
    }

    /// Gebruikt voor `Tag`.
    public struct LabelDTO: Codable, Equatable {
        public var id: UUID
        public var name: String
        public var colorHex: String
        public var isBuiltIn: Bool
        public var createdAt: Date
    }

    public struct MistakeDTO: Codable, Equatable {
        public var id: UUID
        public var name: String
        public var colorHex: String
        public var descriptionText: String
        public var isBuiltIn: Bool
        public var createdAt: Date
    }

    public struct PlaybookRuleDTO: Codable, Equatable {
        public var id: UUID
        public var text: String
        public var sortOrder: Int
    }

    public struct PlaybookDTO: Codable, Equatable {
        public var id: UUID
        public var name: String
        public var descriptionText: String
        public var iconName: String
        public var colorHex: String
        public var isArchived: Bool
        public var createdAt: Date
        public var rules: [PlaybookRuleDTO]
        public var defaultConfluenceIDs: [UUID]
    }

    public struct ExecutionDTO: Codable, Equatable {
        public var id: UUID
        public var date: Date
        public var price: Double
        public var signedQuantity: Double
        public var commission: Double
        public var fees: Double
        public var note: String
    }

    public struct RuleAdherenceDTO: Codable, Equatable {
        public var id: UUID
        public var ruleID: UUID?
        public var followed: Bool
    }

    /// Verwijzing naar een afbeelding in de map `images/` van de zip.
    public struct ScreenshotDTO: Codable, Equatable {
        public var id: UUID
        public var fileName: String
        public var caption: String
        public var sortOrder: Int
        public var createdAt: Date
    }

    public struct TradeDTO: Codable, Equatable {
        public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var symbol: String
        public var direction: String
        public var entryDate: Date
        public var exitDate: Date?
        public var entryPrice: Double
        public var exitPrice: Double?
        public var quantity: Double
        public var stopLoss: Double?
        public var takeProfit: Double?
        public var plannedRisk: Double?
        public var mae: Double?
        public var mfe: Double?
        public var commission: Double
        public var fees: Double
        public var tickSize: Double
        public var tickValue: Double
        public var emotionBefore: String
        public var emotionAfter: String
        public var rating: Int
        public var notes: String
        public var isBacktest: Bool
        public var session: String
        public var accountID: UUID?
        public var instrumentID: UUID?
        public var playbookID: UUID?
        public var confluenceIDs: [UUID]
        public var tagIDs: [UUID]
        public var mistakeIDs: [UUID]
        public var executions: [ExecutionDTO]
        public var ruleAdherence: [RuleAdherenceDTO]
        public var screenshots: [ScreenshotDTO]
    }

    public struct DailyJournalDTO: Codable, Equatable {
        public var id: UUID
        public var date: Date
        public var preMarketPlan: String
        public var dailyBias: String
        public var newsAndEvents: String
        public var postMarketReview: String
        public var mood: String
        public var dayRating: Int
        public var createdAt: Date
        public var updatedAt: Date
        public var screenshots: [ScreenshotDTO]
    }
}
