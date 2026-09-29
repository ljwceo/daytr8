import Foundation

/// Wat de medaille-berekening van één trade nodig heeft. Los van SwiftData,
/// zodat `MedalService` puur te testen is.
struct MedalTradeSnapshot: Equatable, Sendable {
    /// Moment waarop de trade meetelt (exit, of entry zonder exit-tijd).
    let date: Date
    let entryDate: Date
    let outcome: TradeOutcome
    let netPnL: Double
    let rMultiple: Double?
    /// Notities of minstens één screenshot.
    let hasJournal: Bool
    /// Stop-loss of gepland risico ingevuld.
    let hasRiskPlan: Bool
}

/// Resultaat van een medaille-berekening.
struct MedalEvaluation: Equatable, Sendable {
    /// Huidige waarde per medaille-id (voor de voortgangsbalk). Bij win rate
    /// de win rate (0…1).
    let currentValues: [String: Double]
    /// Wanneer elke behaalde medaille (volgens de trades) behaald werd.
    let achievedDates: [String: Date]
    /// Aantal gesloten trades (voor de win rate-medailles).
    let closedTradeCount: Int

    static let empty = MedalEvaluation(currentValues: [:], achievedDates: [:], closedTradeCount: 0)
}

/// Berekent welke medailles (`MedalCatalog`) behaald zijn en hoe ver de
/// gebruiker met de rest is.
///
/// De trades worden chronologisch doorlopen; per medaille wordt het moment
/// bewaard waarop de voorwaarde voor het eerst gehaald werd. Zo kunnen
/// medailles achteraf (bij de eerste start of na een import) met de juiste
/// datum worden toegekend. Eenmaal behaald blijft behaald, ook als bijv. de
/// win rate later zakt.
struct MedalService: Sendable {

    let statsService: StatsService
    let definitions: [MedalDefinition]
    let calendar: Calendar

    init(statsService: StatsService = StatsService(), definitions: [MedalDefinition] = MedalCatalog.all, calendar: Calendar = .current) {
        self.statsService = statsService
        self.definitions = definitions
        self.calendar = calendar
    }

    // MARK: - Invoer

    func snapshots(of trades: [Trade]) -> [MedalTradeSnapshot] {
        trades.map { trade in
            let metrics = statsService.metrics(for: trade)
            let hasNotes = !trade.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return MedalTradeSnapshot(
                date: CalendarAggregationService.referenceDate(for: trade),
                entryDate: trade.entryDate,
                outcome: metrics.outcome,
                netPnL: metrics.netPnL,
                rMultiple: metrics.rMultiple,
                hasJournal: hasNotes || !trade.screenshots.isEmpty,
                hasRiskPlan: trade.stopLoss != nil || (trade.plannedRisk ?? 0) > 0
            )
        }
    }

    func evaluate(_ trades: [Trade]) -> MedalEvaluation {
        evaluate(snapshots: snapshots(of: trades))
    }

    // MARK: - Berekening

    /// Lopende tellers terwijl de trades chronologisch doorlopen worden.
    private struct State {
        var total = 0
        var wins = 0
        var closed = 0
        var netPnL = 0.0
        var currentWinStreak = 0
        var longestWinStreak = 0
        var currentLossStreak = 0
        var journaled = 0
        var riskPlanned = 0
        var lastDay: Date?
        var currentDayStreak = 0
        var longestDayStreak = 0
        var events: Set<MedalEvent> = []

        var winRate: Double { closed == 0 ? 0 : Double(wins) / Double(closed) }
    }

    func evaluate(snapshots: [MedalTradeSnapshot]) -> MedalEvaluation {
        let ordered = snapshots.sorted { $0.date < $1.date }
        var state = State()
        var achieved: [String: Date] = [:]
        let perfectWeekDate = firstPerfectWeek(in: ordered)

        for trade in ordered {
            apply(trade, to: &state)
            if let perfectWeekDate, trade.date >= perfectWeekDate {
                state.events.insert(.perfectWeek)
            }
            for definition in definitions where achieved[definition.id] == nil {
                if isAchieved(definition, state: state) {
                    achieved[definition.id] = trade.date
                }
            }
        }

        var values: [String: Double] = [:]
        for definition in definitions {
            values[definition.id] = value(for: definition, state: state)
        }
        return MedalEvaluation(currentValues: values, achievedDates: achieved, closedTradeCount: state.closed)
    }

    private func apply(_ trade: MedalTradeSnapshot, to state: inout State) {
        state.total += 1
        state.events.insert(.firstTrade)
        if trade.hasJournal { state.journaled += 1 }
        if trade.hasRiskPlan { state.riskPlanned += 1 }

        let hour = calendar.component(.hour, from: trade.entryDate)
        if hour >= 22 || hour < 5 { state.events.insert(.nightOwl) }

        if let r = trade.rMultiple, r >= 5, trade.outcome == .win { state.events.insert(.homeRun) }

        switch trade.outcome {
        case .win:
            if state.currentLossStreak >= 3 { state.events.insert(.comeback) }
            state.wins += 1
            state.closed += 1
            state.netPnL += trade.netPnL
            state.currentWinStreak += 1
            state.longestWinStreak = max(state.longestWinStreak, state.currentWinStreak)
            state.currentLossStreak = 0
        case .loss:
            state.closed += 1
            state.netPnL += trade.netPnL
            state.currentLossStreak += 1
            state.currentWinStreak = 0
        case .breakeven:
            // Net als in `StatsService`: breakeven verbreekt geen streak.
            state.closed += 1
            state.netPnL += trade.netPnL
        case .open:
            break
        }

        updateDayStreak(with: calendar.startOfDay(for: trade.date), state: &state)
    }

    /// Handelsdagen op rij: dagen zonder trades in het weekend breken de reeks niet.
    private func updateDayStreak(with day: Date, state: inout State) {
        defer { state.longestDayStreak = max(state.longestDayStreak, state.currentDayStreak) }
        guard let last = state.lastDay else {
            state.lastDay = day
            state.currentDayStreak = 1
            return
        }
        guard day > last else { return }  // zelfde dag

        var cursor = calendar.date(byAdding: .day, value: 1, to: last) ?? day
        var onlyWeekendBetween = true
        while cursor < day {
            if !calendar.isDateInWeekend(cursor) {
                onlyWeekendBetween = false
                break
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? day
        }
        state.currentDayStreak = onlyWeekendBetween ? state.currentDayStreak + 1 : 1
        state.lastDay = day
    }

    /// Het moment (laatste trade van die week) van de eerste week met minstens
    /// 5 gesloten trades en geen verlies.
    private func firstPerfectWeek(in ordered: [MedalTradeSnapshot]) -> Date? {
        var weeks: [Date: (closed: Int, losses: Int, last: Date)] = [:]
        for trade in ordered where trade.outcome != .open {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: trade.date)?.start else { continue }
            var entry = weeks[week] ?? (0, 0, trade.date)
            entry.closed += 1
            if trade.outcome == .loss { entry.losses += 1 }
            entry.last = max(entry.last, trade.date)
            weeks[week] = entry
        }
        return weeks.values
            .filter { $0.closed >= 5 && $0.losses == 0 }
            .map { $0.last }
            .min()
    }

    private func value(for definition: MedalDefinition, state: State) -> Double {
        switch definition.rule {
        case .winRate:
            return state.winRate
        case .event(let event):
            return state.events.contains(event) ? 1 : 0
        case .count:
            switch definition.category {
            case .totalTrades: return Double(state.total)
            case .winningTrades: return Double(state.wins)
            case .winStreak: return Double(state.longestWinStreak)
            case .activeDays: return Double(state.longestDayStreak)
            case .journaling: return Double(state.journaled)
            case .riskManagement: return Double(state.riskPlanned)
            case .totalProfit: return max(state.netPnL, 0)
            case .winRate: return state.winRate
            case .special: return 0
            }
        }
    }

    private func isAchieved(_ definition: MedalDefinition, state: State) -> Bool {
        switch definition.rule {
        case .count(let target):
            return value(for: definition, state: state) >= target
        case .winRate(let rate, let minimumTrades):
            return state.closed >= minimumTrades && state.winRate >= rate
        case .event(let event):
            return state.events.contains(event)
        }
    }

    // MARK: - Voortgang

    /// Voortgang 0…1 voor de voortgangsbalk.
    static func progress(of definition: MedalDefinition, in evaluation: MedalEvaluation) -> Double {
        let value = evaluation.currentValues[definition.id] ?? 0
        switch definition.rule {
        case .count(let target):
            return target > 0 ? min(value / target, 1) : 1
        case .winRate(let rate, let minimumTrades):
            let tradeProgress = minimumTrades > 0 ? Double(evaluation.closedTradeCount) / Double(minimumTrades) : 1
            let rateProgress = rate > 0 ? value / rate : 1
            return min(tradeProgress, rateProgress, 1)
        case .event:
            return min(value, 1)
        }
    }

    /// Voortgang als tekst, bijv. "37 / 50" of "54% · 80/100 trades".
    static func progressText(of definition: MedalDefinition, in evaluation: MedalEvaluation) -> String {
        let value = evaluation.currentValues[definition.id] ?? 0
        switch definition.rule {
        case .count(let target):
            if definition.category == .totalProfit {
                return "\(MedalCatalog.currency(min(value, target))) / \(MedalCatalog.currency(target))"
            }
            return "\(MedalCatalog.amount(min(value, target))) / \(MedalCatalog.amount(target))"
        case .winRate(let rate, let minimumTrades):
            let current = Int((value * 100).rounded())
            let trades = min(evaluation.closedTradeCount, minimumTrades)
            return "\(current)% / \(Int(rate * 100))% · \(trades)/\(minimumTrades) trades"
        case .event:
            return value >= 1 ? "1 / 1" : "0 / 1"
        }
    }
}
