import Foundation

/// Beoordeling van één dagelijkse regel op één dag.
public struct RuleEvaluation: Identifiable, Equatable, Sendable {
    public let ruleID: UUID
    public let name: String
    public let kind: DailyRuleKind
    public let isFollowed: Bool
    /// Korte uitleg voor de UI (bijv. "2 van max 3 trades").
    public let detail: String

    public var id: UUID { ruleID }
}

/// Resultaat van alle actieve regels op één dag.
public struct DayProgress: Equatable, Sendable {
    public let date: Date
    public let evaluations: [RuleEvaluation]

    /// Of er die dag iets te beoordelen viel: (live) trades, een ingevuld
    /// journal of een afgevinkte regel. Alleen gevolgde dagen tellen mee in
    /// streak en consistentie — een weekend zonder trades breekt geen streak.
    public let isTracked: Bool

    public var ruleCount: Int { evaluations.count }
    public var followedCount: Int { evaluations.filter(\.isFollowed).count }

    /// Aandeel gevolgde regels (0...1); `nil` als er geen regels golden.
    public var score: Double? {
        ruleCount > 0 ? Double(followedCount) / Double(ruleCount) : nil
    }

    /// Alle regels gevolgd (en er was minstens één regel).
    public var isPerfect: Bool { ruleCount > 0 && followedCount == ruleCount }
}

/// Streak en consistentie over een reeks dagen.
public struct ProgressSummary: Equatable, Sendable {
    /// Aantal gevolgde dagen op rij (t/m vandaag) waarop alle regels gevolgd zijn.
    public let currentStreak: Int
    public let longestStreak: Int
    public let trackedDays: Int
    public let perfectDays: Int

    /// `perfectDays / trackedDays`; `nil` zonder gevolgde dagen.
    public var consistency: Double? {
        trackedDays > 0 ? Double(perfectDays) / Double(trackedDays) : nil
    }
}

/// Beoordeelt de dagelijkse regels van de progress tracker (SPEC §10) en
/// berekent streak en consistentie. Puur: werkt op arrays die de caller
/// aanlevert en muteert niets.
///
/// Backtest-trades (`Trade.countsInLiveStats == false`) tellen niet mee.
public struct ProgressTrackerService: Sendable {

    public let statsService: StatsService

    public init(statsService: StatsService = StatsService()) {
        self.statsService = statsService
    }

    // MARK: - Eén dag

    /// Beoordeelt alle regels die op `day` gelden: actief en aangemaakt op of
    /// vóór die dag.
    ///
    /// - Parameters:
    ///   - dayTrades: de trades van die dag (op exit-dag, open trades op entry-dag).
    ///   - checks: afvinkstatussen van handmatige regels (mogen ook andere dagen bevatten).
    public func evaluate(
        rules: [DailyRule],
        on day: Date,
        dayTrades: [Trade],
        journal: DailyJournal?,
        checks: [DailyRuleCheck],
        calendar: Calendar = .current
    ) -> DayProgress {
        let dayStart = calendar.startOfDay(for: day)
        let liveTrades = dayTrades
            .filter(\.countsInLiveStats)
            .sorted { $0.entryDate < $1.entryDate }
        let dayChecks = checks.filter { calendar.isDate($0.date, inSameDayAs: dayStart) }
        let journalFilled = Self.isFilled(journal)

        let evaluations = applicableRules(rules, on: dayStart, calendar: calendar).map { rule in
            evaluate(rule, trades: liveTrades, journalFilled: journalFilled, checks: dayChecks)
        }

        let isTracked = !liveTrades.isEmpty || journalFilled || !dayChecks.isEmpty
        return DayProgress(date: dayStart, evaluations: evaluations, isTracked: isTracked)
    }

    /// Regels die op `day` gelden, in weergavevolgorde.
    public func applicableRules(_ rules: [DailyRule], on day: Date, calendar: Calendar = .current) -> [DailyRule] {
        let dayStart = calendar.startOfDay(for: day)
        return rules
            .filter { $0.isActive && calendar.startOfDay(for: $0.createdAt) <= dayStart }
            .sorted { lhs, rhs in
                lhs.sortOrder != rhs.sortOrder ? lhs.sortOrder < rhs.sortOrder : lhs.createdAt < rhs.createdAt
            }
    }

    private func evaluate(_ rule: DailyRule, trades: [Trade], journalFilled: Bool, checks: [DailyRuleCheck]) -> RuleEvaluation {
        let limit = max(0, Int(rule.threshold.rounded()))
        let followed: Bool
        let detail: String

        switch rule.kind {
        case .manual:
            let check = checks.first { $0.rule?.id == rule.id }
            followed = check?.isFollowed ?? false
            detail = followed ? "Afgevinkt" : "Nog niet afgevinkt"

        case .maxTrades:
            followed = trades.count <= limit
            detail = "\(trades.count) van max \(limit) trades"

        case .stopAfterLosses:
            // Overtreden als er nog een trade geopend is nadat het maximum
            // aantal verliezen al bereikt was.
            var losses = 0
            var tradedAfterLimit = false
            for trade in trades {
                if losses >= limit {
                    tradedAfterLimit = true
                    break
                }
                if statsService.metrics(for: trade).outcome == .loss { losses += 1 }
            }
            let totalLosses = trades.filter { statsService.metrics(for: $0).outcome == .loss }.count
            followed = !tradedAfterLimit
            detail = tradedAfterLimit
                ? "Doorgehandeld na \(Self.losses(limit))"
                : "\(Self.losses(totalLosses)) (stop na \(limit))"

        case .maxDailyLoss:
            let net = trades.reduce(0) { $0 + statsService.metrics(for: $1).netPnL }
            followed = net >= -rule.threshold
            detail = "Dag-P&L \(Self.dollars(net)) (max verlies \(Self.dollars(rule.threshold)))"

        case .journalFilled:
            followed = journalFilled
            detail = journalFilled ? "Journal ingevuld" : "Journal nog leeg"
        }

        return RuleEvaluation(ruleID: rule.id, name: rule.name, kind: rule.kind, isFollowed: followed, detail: detail)
    }

    // MARK: - Meerdere dagen

    /// Beoordeelt elke dag waarop iets te beoordelen valt (trades, journal of
    /// afgevinkte regels), optioneel beperkt tot `range`. Loopt één keer door
    /// elke invoerlijst (O(n)) en beoordeelt daarna per dag.
    public func progress(
        rules: [DailyRule],
        trades: [Trade],
        journals: [DailyJournal],
        checks: [DailyRuleCheck],
        in range: ClosedRange<Date>? = nil,
        calendar: Calendar = .current
    ) -> [Date: DayProgress] {
        var tradesByDay: [Date: [Trade]] = [:]
        for trade in trades where trade.countsInLiveStats {
            tradesByDay[calendar.startOfDay(for: trade.exitDate ?? trade.entryDate), default: []].append(trade)
        }
        var journalsByDay: [Date: DailyJournal] = [:]
        for journal in journals where Self.isFilled(journal) {
            journalsByDay[calendar.startOfDay(for: journal.date)] = journal
        }
        var checksByDay: [Date: [DailyRuleCheck]] = [:]
        for check in checks {
            checksByDay[calendar.startOfDay(for: check.date), default: []].append(check)
        }

        var days = Set(tradesByDay.keys)
        days.formUnion(journalsByDay.keys)
        days.formUnion(checksByDay.keys)
        if let range {
            days = days.filter { range.contains($0) }
        }

        var result: [Date: DayProgress] = [:]
        result.reserveCapacity(days.count)
        for day in days {
            result[day] = evaluate(
                rules: rules,
                on: day,
                dayTrades: tradesByDay[day] ?? [],
                journal: journalsByDay[day],
                checks: checksByDay[day] ?? [],
                calendar: calendar
            )
        }
        return result
    }

    /// Streak en consistentie over de gevolgde dagen in `progress`.
    ///
    /// Alleen dagen met `isTracked` én minstens één regel tellen mee. Vandaag
    /// breekt de huidige streak niet zolang de dag nog niet perfect is: de dag
    /// is dan nog niet voorbij (bijv. journal nog niet ingevuld).
    public func summary(for progress: [Date: DayProgress], today: Date = Date(), calendar: Calendar = .current) -> ProgressSummary {
        let todayStart = calendar.startOfDay(for: today)
        let days = progress.values
            .filter { $0.isTracked && $0.ruleCount > 0 && $0.date <= todayStart }
            .sorted { $0.date < $1.date }

        var longest = 0
        var running = 0
        for day in days {
            running = day.isPerfect ? running + 1 : 0
            longest = max(longest, running)
        }

        var current = 0
        for day in days.reversed() {
            if day.date == todayStart && !day.isPerfect { continue }
            guard day.isPerfect else { break }
            current += 1
        }

        return ProgressSummary(
            currentStreak: current,
            longestStreak: longest,
            trackedDays: days.count,
            perfectDays: days.filter(\.isPerfect).count
        )
    }

    // MARK: - Helpers

    /// Een journal telt als ingevuld zodra het pre-market plan of de
    /// post-market review tekst bevat.
    public static func isFilled(_ journal: DailyJournal?) -> Bool {
        guard let journal else { return false }
        return !journal.preMarketPlan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !journal.postMarketReview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func losses(_ count: Int) -> String {
        count == 1 ? "1 verlies" : "\(count) verliezen"
    }

    private static func dollars(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        return "\(sign)$\(String(format: "%.0f", abs(value)))"
    }
}
