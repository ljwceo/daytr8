import Foundation

/// UI-state voor `ReportsView`: welk tabblad (dimensie) getoond wordt, de
/// sortering daarvan, en — voor de vergelijkingsmodus — twee onafhankelijke
/// filtersets.
///
/// Hergebruikt bewust `DashboardViewModel` voor de filters (account/periode/
/// symbool/playbook/confluence) zodat er precies één plek is die trades
/// filtert, en `DashboardFilterBar` als filter-UI. Elke rapportage-dimensie
/// zelf wordt berekend door `ReportAggregationService`.
@Observable
public final class ReportsViewModel {

    public enum Tab: String, CaseIterable, Identifiable, Sendable {
        case confluence
        case confluenceCombinations
        case playbook
        case symbol
        case direction
        case session
        case dayOfWeek
        case hourOfDay
        case duration
        case tag
        case mistake
        case emotionBefore
        case emotionAfter
        case rating

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .confluence: return "Confluence"
            case .confluenceCombinations: return "Combinaties"
            case .playbook: return "Playbook"
            case .symbol: return "Symbool"
            case .direction: return "Richting"
            case .session: return "Sessie"
            case .dayOfWeek: return "Dag van de week"
            case .hourOfDay: return "Uur van de dag"
            case .duration: return "Trade-duur"
            case .tag: return "Tags"
            case .mistake: return "Fouten"
            case .emotionBefore: return "Emotie vooraf"
            case .emotionAfter: return "Emotie achteraf"
            case .rating: return "Rating"
            }
        }

        /// De dag/uur/duur/rating-tabbladen en de confluentiecombinaties hebben
        /// al een betekenisvolle volgorde (chronologisch of op expectancy) —
        /// die laten we niet door de gebruiker door elkaar laten sorteren.
        public var isUserSortable: Bool {
            switch self {
            case .dayOfWeek, .hourOfDay, .duration, .rating, .confluenceCombinations:
                return false
            default:
                return true
            }
        }
    }

    public enum SortKey: String, CaseIterable, Identifiable, Sendable {
        case netPnL, winRate, tradeCount, expectancy, averageR

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .netPnL: return "Netto P&L"
            case .winRate: return "Win rate"
            case .tradeCount: return "Aantal trades"
            case .expectancy: return "Expectancy"
            case .averageR: return "Gem. R"
            }
        }
    }

    public var selectedTab: Tab = .confluence
    public var sortKey: SortKey = .netPnL
    public var sortAscending: Bool = false
    public var compareMode: Bool = false

    /// Primaire filterset — ook gebruikt als de enige filterset buiten
    /// vergelijkingsmodus.
    public let primaryFilter: DashboardViewModel
    /// Tweede filterset, alleen zichtbaar/relevant in vergelijkingsmodus
    /// (bijv. "met SMT" tegenover "zonder SMT").
    public let secondaryFilter: DashboardViewModel

    public let aggregationService: ReportAggregationService

    public init(
        primaryFilter: DashboardViewModel = DashboardViewModel(),
        secondaryFilter: DashboardViewModel = DashboardViewModel(),
        aggregationService: ReportAggregationService = ReportAggregationService()
    ) {
        self.primaryFilter = primaryFilter
        self.secondaryFilter = secondaryFilter
        self.aggregationService = aggregationService
    }

    public func primaryTrades(_ trades: [Trade]) -> [Trade] {
        primaryFilter.filteredTrades(trades)
    }

    public func secondaryTrades(_ trades: [Trade]) -> [Trade] {
        secondaryFilter.filteredTrades(trades)
    }

    /// Groepeert `trades` volgens `tab` en past — voor de sorteerbare
    /// tabbladen — de gekozen `sortKey`/`sortAscending` toe.
    public func groupResults(for tab: Tab, trades: [Trade]) -> [GroupResult] {
        let raw: [GroupResult]
        switch tab {
        case .confluence: raw = aggregationService.byConfluence(trades)
        case .confluenceCombinations: return aggregationService.byConfluenceCombination(trades)
        case .playbook: raw = aggregationService.byPlaybook(trades)
        case .symbol: raw = aggregationService.bySymbol(trades)
        case .direction: raw = aggregationService.byDirection(trades)
        case .session: raw = aggregationService.bySession(trades)
        case .dayOfWeek: return aggregationService.byDayOfWeek(trades)
        case .hourOfDay: return aggregationService.byHourOfDay(trades)
        case .duration: return aggregationService.byDuration(trades)
        case .tag: raw = aggregationService.byTag(trades)
        case .mistake: raw = aggregationService.byMistake(trades)
        case .emotionBefore: raw = aggregationService.byEmotionBefore(trades)
        case .emotionAfter: raw = aggregationService.byEmotionAfter(trades)
        case .rating: return aggregationService.byRating(trades)
        }
        return applySort(raw)
    }

    private func applySort(_ results: [GroupResult]) -> [GroupResult] {
        // Voor aflopend wordt de vergelijking omgedraaid i.p.v. `.reversed()`
        // op het resultaat toe te passen, zodat gelijke waardes hun relatieve
        // volgorde behouden (stabiele sort) en het returntype `[GroupResult]` blijft.
        results.sorted { lhs, rhs in
            let (a, b) = sortAscending ? (lhs, rhs) : (rhs, lhs)
            switch sortKey {
            case .netPnL: return a.statistics.netPnL < b.statistics.netPnL
            case .winRate: return a.statistics.winRate < b.statistics.winRate
            case .tradeCount: return a.statistics.tradeCount < b.statistics.tradeCount
            case .expectancy: return a.statistics.expectancy < b.statistics.expectancy
            case .averageR:
                return (a.statistics.averageRMultiple ?? -.infinity) < (b.statistics.averageRMultiple ?? -.infinity)
            }
        }
    }
}
