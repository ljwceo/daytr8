import Foundation
import SwiftData

/// Data en journal-bewerklogica voor `DayDetailView` (tik op een dag in de
/// kalender): trades van die dag, intraday cumulatieve P&L en het bijbehorende
/// `DailyJournal`.
@Observable
public final class DayDetailViewModel {

    /// Bewerkbare velden van het dagjournal, losstaand van SwiftData zodat de
    /// view een concept kan bijhouden zonder tussentijds op te slaan.
    public struct JournalDraft: Equatable {
        public var preMarketPlan: String = ""
        public var dailyBias: String = ""
        public var newsAndEvents: String = ""
        public var postMarketReview: String = ""
        public var mood: String = ""
        public var dayRating: Int = 0

        public init(from journal: DailyJournal?) {
            preMarketPlan = journal?.preMarketPlan ?? ""
            dailyBias = journal?.dailyBias ?? ""
            newsAndEvents = journal?.newsAndEvents ?? ""
            postMarketReview = journal?.postMarketReview ?? ""
            mood = journal?.mood ?? ""
            dayRating = journal?.dayRating ?? 0
        }

        /// Leeg concept telt niet als wijziging — voorkomt dat er voor elke
        /// bekeken dag zonder invoer een lege `DailyJournal`-rij ontstaat.
        public var isEmpty: Bool {
            preMarketPlan.isEmpty && dailyBias.isEmpty && newsAndEvents.isEmpty
                && postMarketReview.isEmpty && mood.isEmpty && dayRating == 0
        }
    }

    public let date: Date
    public let statsService: StatsService
    public let templateService: JournalTemplateService
    public var journalDraft: JournalDraft

    public init(
        date: Date,
        journal: DailyJournal?,
        statsService: StatsService = StatsService(),
        templateService: JournalTemplateService = JournalTemplateService()
    ) {
        self.date = date
        self.journalDraft = JournalDraft(from: journal)
        self.statsService = statsService
        self.templateService = templateService
    }

    // MARK: - Templates

    /// Zet `template` in het bijbehorende veld van het concept (pre-market
    /// plan of post-market review), zonder bestaande tekst te overschrijven.
    public func applyTemplate(_ template: JournalTemplate) {
        switch template.kind {
        case .preMarket:
            journalDraft.preMarketPlan = templateService.apply(template.body, to: journalDraft.preMarketPlan, date: date)
        case .postMarket:
            journalDraft.postMarketReview = templateService.apply(template.body, to: journalDraft.postMarketReview, date: date)
        }
    }

    public func resetDraft(from journal: DailyJournal?) {
        journalDraft = JournalDraft(from: journal)
    }

    /// Trades van deze dag: geteld op hun exit-dag, of entry-dag als ze nog open zijn.
    public func trades(from allTrades: [Trade], calendar: Calendar = .current) -> [Trade] {
        allTrades
            .filter { calendar.isDate($0.exitDate ?? $0.entryDate, inSameDayAs: date) }
            .sorted { $0.entryDate < $1.entryDate }
    }

    public func statistics(for dayTrades: [Trade]) -> TradeStatistics {
        statsService.statistics(for: dayTrades)
    }

    public func intradayEquityPoints(for dayTrades: [Trade]) -> [DateValuePoint] {
        statsService.equityCurve(for: dayTrades).map { DateValuePoint(date: $0.date, value: $0.equity) }
    }

    /// Maakt of werkt het `DailyJournal` van deze dag bij met `journalDraft`.
    /// Slaat niets op als het concept leeg is en er nog geen bestaand journal was.
    @discardableResult
    public func saveJournal(existing: DailyJournal?, in context: ModelContext) -> DailyJournal? {
        if journalDraft.isEmpty, existing == nil { return nil }

        let journal = existing ?? DailyJournal(date: date)
        if existing == nil {
            context.insert(journal)
        }
        journal.preMarketPlan = journalDraft.preMarketPlan
        journal.dailyBias = journalDraft.dailyBias
        journal.newsAndEvents = journalDraft.newsAndEvents
        journal.postMarketReview = journalDraft.postMarketReview
        journal.mood = journalDraft.mood
        journal.dayRating = journalDraft.dayRating
        journal.updatedAt = Date()
        return journal
    }
}
