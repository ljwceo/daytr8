import Foundation
import SwiftData

/// Journal-entry voor één handelsdag.
///
/// Bevat pre-market plan, bias, nieuws/events, post-market review, mood en een
/// cijfer voor de dag. Screenshots (charts, news feed) worden aan de entry
/// gekoppeld.
@Model
public final class DailyJournal {

    public var id: UUID = UUID()

    /// Datum van de handelsdag (op middernacht, in de gebruikers-tijdzone).
    public var date: Date = Date()

    // MARK: - Inhoud

    public var preMarketPlan: String = ""
    public var dailyBias: String = ""
    public var newsAndEvents: String = ""
    public var postMarketReview: String = ""

    /// Vrije tekst-mood ("scherp", "moe", "gefrustreerd", ...).
    public var mood: String = ""

    /// Cijfer 1..10 voor de dag (0 = niet ingevuld).
    public var dayRating: Int = 0

    // MARK: - Metadata

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    // MARK: - Relaties

    @Relationship(deleteRule: .cascade)
    public var screenshots: [DailyJournalScreenshot] = []

    public init(
        id: UUID = UUID(),
        date: Date,
        preMarketPlan: String = "",
        dailyBias: String = "",
        newsAndEvents: String = "",
        postMarketReview: String = "",
        mood: String = "",
        dayRating: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.preMarketPlan = preMarketPlan
        self.dailyBias = dailyBias
        self.newsAndEvents = newsAndEvents
        self.postMarketReview = postMarketReview
        self.mood = mood
        self.dayRating = dayRating
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Screenshot bij een `DailyJournal`.
@Model
public final class DailyJournalScreenshot {

    public var id: UUID = UUID()

    @Attribute(.externalStorage)
    public var imageData: Data = Data()

    public var caption: String = ""
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()

    public var journal: DailyJournal?

    public init(
        id: UUID = UUID(),
        imageData: Data,
        caption: String = "",
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.imageData = imageData
        self.caption = caption
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
