import Foundation

/// Data van de jaar-heatmap voor één jaar.
public struct HeatmapYearData: Equatable, Sendable {
    public let year: Int
    public let metric: WidgetSettings.HeatmapMetric
    /// Waarde per dag (start van de dag). Alleen dagen met een waarde.
    public let values: [Date: Double]
    /// Samenvattend getal rechtsboven (jaartotaal of jaar-win rate).
    public let summary: Double?
    /// Grootste absolute waarde (voor de kleurschaal).
    public let maxMagnitude: Double
    /// Jaren met trades (voor de navigatie), oplopend.
    public let availableYears: [Int]

    /// Kleurintensiteit van een dag: -1…1 voor een uitwaaierende schaal
    /// (P&L, R, win rate rond 50%) en 0…1 voor aantallen. `nil` = geen data.
    public func normalizedValue(for day: Date) -> Double? {
        guard let value = values[day] else { return nil }
        switch metric {
        case .winRate:
            return min(max((value - 0.5) * 2, -1), 1)
        case .tradeCount, .netPnL, .rMultiple:
            guard maxMagnitude > 0 else { return 0 }
            return min(max(value / maxMagnitude, -1), 1)
        }
    }

    /// `true` als de kleurschaal van verlies naar winst loopt (anders van weinig naar veel).
    public var isDiverging: Bool { metric != .tradeCount }
}

/// Eén staaf van het R-multiple-histogram.
public struct RMultipleBucket: Identifiable, Equatable, Sendable {
    /// Ondergrens (inclusief); `-infinity` voor de onderste overloop-bak.
    public let lowerBound: Double
    /// Bovengrens (exclusief); `infinity` voor de bovenste overloop-bak.
    public let upperBound: Double
    public let count: Int

    public var id: Double { lowerBound }

    public var label: String {
        if lowerBound == -.infinity { return "<\(Self.format(upperBound))" }
        if upperBound == .infinity { return "≥\(Self.format(lowerBound))" }
        return Self.format(lowerBound)
    }

    /// Verliesbak (helemaal onder 0R).
    public var isLoss: Bool { upperBound <= 0 }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0fR", value) : String(format: "%.1fR", value)
    }
}

/// Vergelijking van een kengetal met de vorige periode.
public struct MetricComparison: Equatable, Sendable {
    public let current: Double?
    public let previous: Double?

    public var change: Double? {
        guard let current, let previous, current.isFinite, previous.isFinite else { return nil }
        return current - previous
    }
}

/// Berekeningen voor de dashboardwidgets.
///
/// Bevat zelf geen statistiek: filteren gaat via `DashboardViewModel`
/// (dezelfde filters als het dashboard), cijfers via `StatsService`,
/// dagtotalen via `CalendarAggregationService` en groeperingen via
/// `ReportAggregationService`. Deze service combineert ze per widget.
public struct WidgetDataService: Sendable {

    public let statsService: StatsService
    public let aggregationService: CalendarAggregationService
    public let reportService: ReportAggregationService

    public init(statsService: StatsService = StatsService()) {
        self.statsService = statsService
        self.aggregationService = CalendarAggregationService(statsService: statsService)
        self.reportService = ReportAggregationService(statsService: statsService)
    }

    // MARK: - Filters

    /// De filters waarmee een widget rekent: die van het dashboard, met de
    /// periode en accounts van de widget als die afwijken.
    public func effectiveFilter(base: DashboardFilterState, settings: WidgetSettings, includePeriod: Bool = true) -> DashboardFilterState {
        var state = base
        if includePeriod, let period = settings.period.dashboardPeriod {
            state.period = period.rawValue
            if period == .custom {
                state.customStart = settings.customRange?.lowerBound
                state.customEnd = settings.customRange?.upperBound
            }
        }
        if !includePeriod {
            state.period = DashboardViewModel.Period.all.rawValue
        }
        if !settings.accountIDs.isEmpty {
            state.selectedAccountIDs = settings.accountIDs
        }
        return state
    }

    /// Trades volgens `state` (zelfde logica als de dashboardfilters).
    public func trades(_ trades: [Trade], matching state: DashboardFilterState, now: Date = Date(), calendar: Calendar = .current) -> [Trade] {
        let filter = DashboardViewModel(statsService: statsService)
        filter.apply(state)
        return filter.filteredTrades(trades, now: now, calendar: calendar)
    }

    /// De periode vóór de periode van `state` (vorige week/maand/jaar/dag,
    /// of een even lange periode vóór een aangepaste). `nil` bij "Alles".
    public func previousFilter(of state: DashboardFilterState, now: Date = Date(), calendar: Calendar = .current) -> DashboardFilterState? {
        let filter = DashboardViewModel(statsService: statsService)
        filter.apply(state)
        guard let range = filter.periodRange(now: now, calendar: calendar) else { return nil }

        let previous: ClosedRange<Date>?
        switch filter.period {
        case .all:
            previous = nil
        case .today:
            previous = Self.shifted(range, by: .day, calendar: calendar)
        case .thisWeek:
            previous = Self.shifted(range, by: .weekOfYear, calendar: calendar)
        case .thisMonth:
            previous = Self.shifted(range, by: .month, calendar: calendar)
        case .thisYear:
            previous = Self.shifted(range, by: .year, calendar: calendar)
        case .custom:
            let length = range.upperBound.timeIntervalSince(range.lowerBound)
            let end = range.lowerBound.addingTimeInterval(-1)
            previous = end.addingTimeInterval(-length)...end
        }
        guard let previous else { return nil }

        var result = state
        result.period = DashboardViewModel.Period.custom.rawValue
        result.customStart = previous.lowerBound
        result.customEnd = previous.upperBound
        return result
    }

    private static func shifted(_ range: ClosedRange<Date>, by component: Calendar.Component, calendar: Calendar) -> ClosedRange<Date>? {
        guard let start = calendar.date(byAdding: component, value: -1, to: range.lowerBound) else { return nil }
        // Eind exclusief van de periode zelf, zodat een trade op de grens niet dubbel telt.
        return start...range.lowerBound.addingTimeInterval(-0.001)
    }

    // MARK: - Statistiekkaart

    /// Numerieke waarde van een kengetal (`nil` = niet te bepalen of niet
    /// zinvol om te vergelijken, zoals "gem. winst / verlies").
    public func value(of metric: WidgetSettings.Metric, in stats: TradeStatistics) -> Double? {
        switch metric {
        case .netPnL: return stats.netPnL
        case .winRate: return stats.tradeCount > 0 ? stats.winRate : nil
        case .profitFactor:
            guard let factor = stats.profitFactor, factor.isFinite else { return nil }
            return factor
        case .expectancy: return stats.expectancy
        case .averageR: return stats.averageRMultiple
        case .maxDrawdown: return stats.maxDrawdown
        case .tradeCount: return Double(stats.tradeCount)
        case .streak:
            guard let winning = stats.currentStreakIsWinning else { return nil }
            return Double(winning ? stats.currentStreak : -stats.currentStreak)
        case .averageWinLoss, .largestWinLoss:
            return nil
        }
    }

    /// Huidige waarde en die van de vorige periode.
    public func comparison(
        of metric: WidgetSettings.Metric,
        trades all: [Trade],
        state: DashboardFilterState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MetricComparison {
        let current = statsService.statistics(for: trades(all, matching: state, now: now, calendar: calendar))
        let currentValue = value(of: metric, in: current)
        guard metric != .streak, let previousState = previousFilter(of: state, now: now, calendar: calendar) else {
            return MetricComparison(current: currentValue, previous: nil)
        }
        let previousTrades = trades(all, matching: previousState, now: now, calendar: calendar)
        guard !previousTrades.isEmpty else { return MetricComparison(current: currentValue, previous: nil) }
        return MetricComparison(current: currentValue, previous: value(of: metric, in: statsService.statistics(for: previousTrades)))
    }

    // MARK: - Jaar-heatmap

    /// Waarden per dag voor `year`. Loopt één keer door de trades: eerst
    /// filteren op het jaar, dan dagaggregaten (zelfde bron als de kalender).
    public func heatmap(
        for trades: [Trade],
        year: Int,
        metric: WidgetSettings.HeatmapMetric,
        calendar: Calendar = .current
    ) -> HeatmapYearData {
        var years = Set<Int>()
        var yearTrades: [Trade] = []
        for trade in trades {
            let tradeYear = calendar.component(.year, from: CalendarAggregationService.referenceDate(for: trade))
            years.insert(tradeYear)
            if tradeYear == year { yearTrades.append(trade) }
        }

        var values: [Date: Double] = [:]
        let summary: Double?
        switch metric {
        case .netPnL, .tradeCount, .winRate:
            let days = aggregationService.dayAggregates(for: yearTrades, calendar: calendar)
            for (day, aggregate) in days {
                switch metric {
                case .netPnL:
                    if aggregate.winCount + aggregate.lossCount + aggregate.breakevenCount > 0 { values[day] = aggregate.netPnL }
                case .tradeCount:
                    values[day] = Double(aggregate.tradeCount)
                case .winRate:
                    if aggregate.winCount + aggregate.lossCount + aggregate.breakevenCount > 0 { values[day] = aggregate.winRate }
                case .rMultiple:
                    break
                }
            }
            let stats = statsService.statistics(for: yearTrades)
            switch metric {
            case .netPnL: summary = yearTrades.isEmpty ? nil : stats.netPnL
            case .tradeCount: summary = Double(yearTrades.count)
            case .winRate: summary = stats.winCount + stats.lossCount + stats.breakevenCount > 0 ? stats.winRate : nil
            case .rMultiple: summary = nil
            }
        case .rMultiple:
            var total: Double?
            for trade in yearTrades {
                let metrics = statsService.metrics(for: trade)
                guard metrics.outcome != .open, let r = metrics.rMultiple else { continue }
                let day = calendar.startOfDay(for: CalendarAggregationService.referenceDate(for: trade))
                values[day, default: 0] += r
                total = (total ?? 0) + r
            }
            summary = total
        }

        let maxMagnitude = values.values.map { abs($0) }.max() ?? 0
        return HeatmapYearData(
            year: year,
            metric: metric,
            values: values,
            summary: summary,
            maxMagnitude: maxMagnitude,
            availableYears: years.sorted()
        )
    }

    // MARK: - R-multiple-histogram

    /// Verdeling van de R-multiples van gesloten trades in bakken van
    /// `bucketWidth`, van `lowerLimit` tot `upperLimit` plus een overloop-bak
    /// aan beide kanten. Lege bakken tussenin blijven staan (doorlopende as).
    public func rHistogram(
        for trades: [Trade],
        bucketWidth: Double = 0.5,
        lowerLimit: Double = -3,
        upperLimit: Double = 5
    ) -> [RMultipleBucket] {
        let rValues = trades.compactMap { trade -> Double? in
            let metrics = statsService.metrics(for: trade)
            guard metrics.outcome != .open else { return nil }
            return metrics.rMultiple
        }
        guard !rValues.isEmpty, bucketWidth > 0, upperLimit > lowerLimit else { return [] }

        let bucketCount = Int(((upperLimit - lowerLimit) / bucketWidth).rounded())
        var counts = [Int](repeating: 0, count: bucketCount)
        var below = 0
        var above = 0
        for r in rValues {
            if r < lowerLimit {
                below += 1
            } else if r >= upperLimit {
                above += 1
            } else {
                let index = min(Int(((r - lowerLimit) / bucketWidth).rounded(.down)), bucketCount - 1)
                counts[index] += 1
            }
        }

        var buckets: [RMultipleBucket] = []
        if below > 0 { buckets.append(RMultipleBucket(lowerBound: -.infinity, upperBound: lowerLimit, count: below)) }
        for index in 0..<bucketCount {
            let lower = lowerLimit + Double(index) * bucketWidth
            buckets.append(RMultipleBucket(lowerBound: lower, upperBound: lower + bucketWidth, count: counts[index]))
        }
        if above > 0 { buckets.append(RMultipleBucket(lowerBound: upperLimit, upperBound: .infinity, count: above)) }
        return buckets
    }

    // MARK: - Top/flop

    /// Beste en slechtste groepen op netto P&L. Een groep komt nooit in
    /// beide lijsten: bij weinig groepen krijgt "top" de winnende helft.
    public func topFlop(for trades: [Trade], dimension: WidgetSettings.Dimension, count: Int) -> (top: [GroupResult], flop: [GroupResult]) {
        let groups: [GroupResult]
        switch dimension {
        case .symbol: groups = reportService.bySymbol(trades)
        case .confluence: groups = reportService.byConfluence(trades)
        case .playbook: groups = reportService.byPlaybook(trades)
        case .session: groups = reportService.bySession(trades)
        }
        let closed = groups.filter { $0.statistics.tradeCount > $0.statistics.openCount }
        let sorted = closed.sorted { lhs, rhs in
            lhs.statistics.netPnL != rhs.statistics.netPnL ? lhs.statistics.netPnL > rhs.statistics.netPnL : lhs.label < rhs.label
        }
        let limit = max(count, 1)
        let topCount = min(limit, (sorted.count + 1) / 2)
        let top = Array(sorted.prefix(topCount))
        let flopCount = min(limit, sorted.count - topCount)
        let flop = Array(sorted.suffix(flopCount).reversed())
        return (top, flop)
    }
}

/// Eenvoudige cache voor widgetberekeningen tussen renders.
///
/// Elke widget rekent op dezelfde tradelijst; zolang die niet verandert
/// (`version`, bijv. aantal trades + laatste wijziging) worden resultaten
/// per sleutel hergebruikt. Bij een nieuwe versie wordt alles gewist. Zo
/// blijft het dashboard soepel, ook met jaren aan data en veel widgets.
public final class WidgetComputationCache {

    private var version: String = ""
    private var storage: [String: Any] = [:]

    public init() {}

    public func value<T>(_ key: String, version: String, compute: () -> T) -> T {
        if version != self.version {
            storage.removeAll(keepingCapacity: true)
            self.version = version
        }
        if let cached = storage[key] as? T { return cached }
        let value = compute()
        storage[key] = value
        return value
    }

    /// Versiesleutel voor een tradelijst: aantal, laatste wijziging en de
    /// huidige dag (periodes als "deze week" schuiven met de datum mee).
    public static func version(for trades: [Trade], extra: String = "", now: Date = Date(), calendar: Calendar = .current) -> String {
        let latest = trades.reduce(0.0) { max($0, $1.updatedAt.timeIntervalSince1970) }
        let day = calendar.startOfDay(for: now).timeIntervalSince1970
        return "\(trades.count)|\(latest)|\(day)|\(extra)"
    }
}
