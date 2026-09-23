import Foundation

/// Hoe dicht een limiet (daily loss / max drawdown) benaderd is.
public enum GoalLevel: Int, Comparable, Sendable {
    case ok
    case warning
    case breached

    public static func < (lhs: GoalLevel, rhs: GoalLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Voortgang richting een doel (maandelijks P&L-doel).
public struct TargetProgress: Equatable, Sendable {
    public let current: Double
    public let target: Double

    /// `current / target`, begrensd op 0...1 voor een voortgangsbalk.
    public var fraction: Double {
        guard target > 0 else { return 0 }
        return min(max(current / target, 0), 1)
    }

    public var isReached: Bool { target > 0 && current >= target }
}

/// Gebruik van een verlieslimiet (daily loss limit, max drawdown).
public struct LimitStatus: Equatable, Sendable {
    /// Verbruikt verlies in $, altijd ≥ 0.
    public let used: Double
    public let limit: Double
    public let level: GoalLevel

    /// `used / limit`, begrensd op 0...1 voor een voortgangsbalk.
    public var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(max(used / limit, 0), 1)
    }

    /// Resterende ruimte tot de limiet, ≥ 0.
    public var remaining: Double { max(limit - used, 0) }
}

/// Doelen en limieten van één account.
public struct AccountGoalStatus: Identifiable, Equatable, Sendable {
    public let accountID: UUID
    public let accountName: String
    public let currency: String
    public let monthlyTarget: TargetProgress?
    public let dailyLoss: LimitStatus?
    public let drawdown: LimitStatus?

    public var id: UUID { accountID }

    /// Ernstigste niveau van de limieten van dit account.
    public var level: GoalLevel {
        max(dailyLoss?.level ?? .ok, drawdown?.level ?? .ok)
    }
}

/// Berekent de voortgang van accountdoelen (SPEC §10): maandelijks P&L-doel,
/// daily loss limit en max drawdown (voor prop firm-accounts), met een
/// waarschuwing zodra `warningFraction` van een limiet verbruikt is.
public struct GoalsService: Sendable {

    /// Vanaf dit aandeel van een limiet toont de app een waarschuwing.
    public static let defaultWarningFraction = 0.8

    public let statsService: StatsService
    public let warningFraction: Double

    public init(statsService: StatsService = StatsService(), warningFraction: Double = GoalsService.defaultWarningFraction) {
        self.statsService = statsService
        self.warningFraction = warningFraction
    }

    public func limitStatus(used: Double, limit: Double) -> LimitStatus {
        let used = max(used, 0)
        let level: GoalLevel
        if limit > 0, used >= limit {
            level = .breached
        } else if limit > 0, used >= limit * warningFraction {
            level = .warning
        } else {
            level = .ok
        }
        return LimitStatus(used: used, limit: limit, level: level)
    }

    /// Doelstatus van `account` op basis van zijn (gesloten) trades.
    /// Geeft `nil` als het account geen enkel doel of limiet heeft.
    ///
    /// - Maanddoel: netto P&L van trades met exit in de huidige maand.
    /// - Daily loss: verlies van trades met exit vandaag.
    /// - Drawdown: huidige afstand van de hoogste equity (startbalans +
    ///   cumulatieve P&L) tot de huidige equity — trailing, zoals prop firms rekenen.
    public func status(for account: Account, trades allTrades: [Trade], now: Date = Date(), calendar: Calendar = .current) -> AccountGoalStatus? {
        let target = positive(account.monthlyProfitTarget)
        let dailyLimit = positive(account.dailyLossLimit)
        let maxDrawdown = positive(account.maxDrawdown)
        guard target != nil || dailyLimit != nil || maxDrawdown != nil else { return nil }

        // Backtest-trades binnen een live account tellen niet mee; binnen een
        // backtest-account juist wel (dat zijn z'n eigen doelen).
        let trades = allTrades.filter { trade in
            trade.account?.id == account.id && (trade.countsInLiveStats || account.type == .backtest)
        }

        let monthly = target.map { target in
            TargetProgress(current: netPnL(of: trades, closedIn: .month, of: now, calendar: calendar), target: target)
        }
        let daily = dailyLimit.map { limit in
            limitStatus(used: -netPnL(of: trades, closedIn: .day, of: now, calendar: calendar), limit: limit)
        }
        let drawdown = maxDrawdown.map { limit in
            let current = statsService.drawdownCurve(for: trades, startingBalance: account.startingBalance).last?.drawdown ?? 0
            return limitStatus(used: current, limit: limit)
        }

        return AccountGoalStatus(
            accountID: account.id,
            accountName: account.name,
            currency: account.currency,
            monthlyTarget: monthly,
            dailyLoss: daily,
            drawdown: drawdown
        )
    }

    /// Doelstatus van alle niet-gearchiveerde accounts met minstens één doel.
    public func statuses(accounts: [Account], trades: [Trade], now: Date = Date(), calendar: Calendar = .current) -> [AccountGoalStatus] {
        accounts
            .filter { !$0.isArchived }
            .compactMap { status(for: $0, trades: trades, now: now, calendar: calendar) }
    }

    // MARK: - Helpers

    private func netPnL(of trades: [Trade], closedIn component: Calendar.Component, of now: Date, calendar: Calendar) -> Double {
        guard let interval = calendar.dateInterval(of: component, for: now) else { return 0 }
        return trades.reduce(0) { sum, trade in
            guard let exit = trade.exitDate, interval.contains(exit) else { return sum }
            let metrics = statsService.metrics(for: trade)
            return metrics.outcome == .open ? sum : sum + metrics.netPnL
        }
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
