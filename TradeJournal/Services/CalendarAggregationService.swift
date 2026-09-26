import Foundation

/// Statistieken voor één handelsdag, gebruikt door de kalendermaand-cellen,
/// de mini-kalender op het dashboard en de weektotalen-kolom.
public struct DayAggregate: Equatable, Sendable {
    public let date: Date
    public let netPnL: Double
    public let grossPnL: Double
    public let tradeCount: Int
    public let winCount: Int
    public let lossCount: Int
    public let breakevenCount: Int
    public let openCount: Int
    public let winRate: Double
}

/// Statistieken voor één maand, gebruikt door het jaaroverzicht (heatmap).
public struct MonthAggregate: Equatable, Sendable {
    public let month: Date
    public let netPnL: Double
    public let tradeCount: Int
}

/// Groepeert trades per dag/maand voor de kalender en het dashboard.
///
/// Een dag- of maandcel filtert nooit zelf de volledige tradelijst: deze service
/// loopt één keer (O(n)) door alle trades en bouwt een dictionary op dagniveau,
/// zodat elke cel daarna een O(1) lookup doet. Dat houdt de kalender soepel bij
/// jaren aan data, ook zonder een aparte, tussen renders bewaarde cache.
public struct CalendarAggregationService: Sendable {

    public let statsService: StatsService

    public init(statsService: StatsService = StatsService()) {
        self.statsService = statsService
    }

    /// Het moment waarop een trade in de kalender (en in doelen/limieten)
    /// meetelt: de exit, of de entry als er geen exit-tijd is — bijv. een
    /// uitgebreide trade met exit-prijs maar zonder ingevulde exit-tijd.
    public static func referenceDate(for trade: Trade) -> Date {
        trade.exitDate ?? trade.entryDate
    }

    /// Groepeert `trades` per dag. Een trade telt mee op de dag van zijn exit;
    /// zonder exit-tijd op zijn entry-dag (zie `referenceDate(for:)`).
    public func dayAggregates(for trades: [Trade], calendar: Calendar = .current) -> [Date: DayAggregate] {
        var byDay: [Date: [Trade]] = [:]
        for trade in trades {
            let day = calendar.startOfDay(for: Self.referenceDate(for: trade))
            byDay[day, default: []].append(trade)
        }

        var result: [Date: DayAggregate] = [:]
        result.reserveCapacity(byDay.count)
        for (day, dayTrades) in byDay {
            let stats = statsService.statistics(for: dayTrades)
            result[day] = DayAggregate(
                date: day,
                netPnL: stats.netPnL,
                grossPnL: stats.grossPnL,
                tradeCount: dayTrades.count,
                winCount: stats.winCount,
                lossCount: stats.lossCount,
                breakevenCount: stats.breakevenCount,
                openCount: stats.openCount,
                winRate: stats.winRate
            )
        }
        return result
    }

    /// Netto P&L (na kosten, alleen gesloten trades) van alle dagen in
    /// `interval` (start inclusief, eind exclusief). Bouwt op dezelfde
    /// dagaggregaten als de kalender, zodat maanddoel, daily loss limit en
    /// kalender-/weektotalen nooit uit elkaar kunnen lopen.
    public func netPnL(of trades: [Trade], in interval: DateInterval, calendar: Calendar = .current) -> Double {
        dayAggregates(for: trades, calendar: calendar).values.reduce(0) { sum, day in
            day.date >= interval.start && day.date < interval.end ? sum + day.netPnL : sum
        }
    }

    /// Netto P&L van de dag/week/maand/jaar (`component`) waarin `date` valt,
    /// in de tijdzone van `calendar`.
    public func netPnL(of trades: [Trade], periodOf component: Calendar.Component, containing date: Date, calendar: Calendar = .current) -> Double {
        guard let interval = calendar.dateInterval(of: component, for: date) else { return 0 }
        return netPnL(of: trades, in: interval, calendar: calendar)
    }

    /// Rolt dagaggregaten op naar maandtotalen voor het jaaroverzicht.
    public func monthAggregates(fromDayAggregates dayAggregates: [Date: DayAggregate], calendar: Calendar = .current) -> [Date: MonthAggregate] {
        var byMonth: [Date: (netPnL: Double, tradeCount: Int)] = [:]
        for (day, aggregate) in dayAggregates {
            let comps = calendar.dateComponents([.year, .month], from: day)
            guard let monthStart = calendar.date(from: comps) else { continue }
            var entry = byMonth[monthStart] ?? (0, 0)
            entry.netPnL += aggregate.netPnL
            entry.tradeCount += aggregate.tradeCount
            byMonth[monthStart] = entry
        }

        var result: [Date: MonthAggregate] = [:]
        result.reserveCapacity(byMonth.count)
        for (month, totals) in byMonth {
            result[month] = MonthAggregate(month: month, netPnL: totals.netPnL, tradeCount: totals.tradeCount)
        }
        return result
    }
}
