import Foundation
import SwiftData

/// Eén punt in een tijdreeks-grafiek (equity curve, drawdown, dagelijkse P&L).
public struct DateValuePoint: Identifiable, Equatable {
    public let id: Date
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.id = date
        self.date = date
        self.value = value
    }
}

/// Filters, statistieken en grafiekdata voor `DashboardView`.
///
/// Houdt alleen filter-state vast; alle afgeleide data (statistieken,
/// grafiekpunten, trading score) wordt puur berekend uit de trades die de
/// view via `@Query` aanlevert, zodat dit stateless en unit-testbaar blijft.
@Observable
public final class DashboardViewModel {

    public enum Period: String, CaseIterable, Identifiable, Sendable {
        case today, thisWeek, thisMonth, thisYear, all, custom

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .today: return "Vandaag"
            case .thisWeek: return "Deze week"
            case .thisMonth: return "Deze maand"
            case .thisYear: return "Dit jaar"
            case .all: return "Alles"
            case .custom: return "Aangepast"
            }
        }
    }

    public var selectedAccountIDs: Set<UUID> = []
    public var period: Period = .all
    public var customRange: ClosedRange<Date>?
    public var symbolFilter: String?
    public var playbookID: UUID?
    public var confluenceID: UUID?

    /// Backtest-modus (SPEC §10): standaard tellen backtest-trades niet mee in
    /// de statistieken. Een expliciet geselecteerd account telt altijd mee,
    /// zodat een backtest-account los te analyseren is.
    public var includeBacktest: Bool = false

    public let statsService: StatsService
    public let aggregationService: CalendarAggregationService
    public let scoreService: TradingScoreService
    public let goalsService: GoalsService

    public init(
        statsService: StatsService = StatsService(),
        aggregationService: CalendarAggregationService = CalendarAggregationService(),
        scoreService: TradingScoreService = TradingScoreService(),
        goalsService: GoalsService = GoalsService()
    ) {
        self.statsService = statsService
        self.aggregationService = aggregationService
        self.scoreService = scoreService
        self.goalsService = goalsService
    }

    // MARK: - Accountfilter

    public func isAccountSelected(_ account: Account) -> Bool {
        selectedAccountIDs.isEmpty || selectedAccountIDs.contains(account.id)
    }

    public func toggleAccount(_ account: Account) {
        if selectedAccountIDs.contains(account.id) {
            selectedAccountIDs.remove(account.id)
        } else {
            selectedAccountIDs.insert(account.id)
        }
    }

    // MARK: - Periodefilter

    public func periodRange(now: Date, calendar: Calendar) -> ClosedRange<Date>? {
        switch period {
        case .all:
            return nil
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return start...end
        case .thisWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
            return interval.start...interval.end
        case .thisMonth:
            guard let interval = calendar.dateInterval(of: .month, for: now) else { return nil }
            return interval.start...interval.end
        case .thisYear:
            guard let interval = calendar.dateInterval(of: .year, for: now) else { return nil }
            return interval.start...interval.end
        case .custom:
            return customRange
        }
    }

    // MARK: - Filteren

    public func filteredTrades(_ trades: [Trade], now: Date = Date(), calendar: Calendar = .current) -> [Trade] {
        var result = trades

        if !includeBacktest {
            result = result.filter { trade in
                trade.countsInLiveStats || (trade.account.map { selectedAccountIDs.contains($0.id) } ?? false)
            }
        }
        if !selectedAccountIDs.isEmpty {
            result = result.filter { trade in trade.account.map { selectedAccountIDs.contains($0.id) } ?? false }
        }
        if let range = periodRange(now: now, calendar: calendar) {
            result = result.filter { range.contains($0.entryDate) }
        }
        if let symbolFilter, !symbolFilter.isEmpty {
            result = result.filter { $0.symbol == symbolFilter }
        }
        if let playbookID {
            result = result.filter { $0.playbook?.id == playbookID }
        }
        if let confluenceID {
            result = result.filter { trade in trade.confluences.contains { $0.id == confluenceID } }
        }

        return result
    }

    public func availableSymbols(from trades: [Trade]) -> [String] {
        Array(Set(trades.map(\.symbol))).sorted()
    }

    // MARK: - Statistieken & grafieken

    public func statistics(for trades: [Trade]) -> TradeStatistics {
        statsService.statistics(for: trades)
    }

    public func equityPoints(for trades: [Trade]) -> [DateValuePoint] {
        statsService.equityCurve(for: trades).map { DateValuePoint(date: $0.date, value: $0.equity) }
    }

    /// Drawdown als negatieve waarde, zodat de grafiek onder de nullijn duikt
    /// zoals traders een drawdown-chart gewend zijn te lezen.
    public func drawdownPoints(for trades: [Trade]) -> [DateValuePoint] {
        statsService.drawdownCurve(for: trades).map { DateValuePoint(date: $0.date, value: -$0.drawdown) }
    }

    public func dailyPnLPoints(for trades: [Trade], calendar: Calendar = .current) -> [DateValuePoint] {
        aggregationService.dayAggregates(for: trades, calendar: calendar)
            .values
            .sorted { $0.date < $1.date }
            .map { DateValuePoint(date: $0.date, value: $0.netPnL) }
    }

    public func ruleAdherenceRate(for trades: [Trade]) -> Double? {
        let adherences = trades.flatMap(\.ruleAdherence)
        guard !adherences.isEmpty else { return nil }
        let followed = adherences.filter(\.followed).count
        return Double(followed) / Double(adherences.count)
    }

    public func tradingScore(for trades: [Trade], calendar: Calendar = .current) -> TradingScore {
        let stats = statistics(for: trades)
        let dailyPnL = dailyPnLPoints(for: trades, calendar: calendar).map(\.value)
        return scoreService.score(for: stats, dailyNetPnL: dailyPnL, ruleAdherenceRate: ruleAdherenceRate(for: trades))
    }

    // MARK: - Doelen

    /// Doelen en limieten per account, los van de dashboardfilters (een
    /// daily loss limit geldt altijd voor vandaag, ongeacht de gekozen periode).
    public func goalStatuses(accounts: [Account], trades: [Trade], now: Date = Date(), calendar: Calendar = .current) -> [AccountGoalStatus] {
        goalsService.statuses(accounts: accounts, trades: trades, now: now, calendar: calendar)
    }

    public func recentTrades(from trades: [Trade], limit: Int = 5) -> [Trade] {
        Array(trades.sorted { ($0.exitDate ?? $0.entryDate) > ($1.exitDate ?? $1.entryDate) }.prefix(limit))
    }
}
