import Foundation

/// Berekeningen voor één individuele trade.
public struct TradeMetrics: Equatable, Sendable {
    /// Aantal ticks (met teken) tussen entry en gemiddelde exit.
    public let signedTicks: Double
    /// Bruto P&L (zonder commissies/fees).
    public let grossPnL: Double
    /// Netto P&L (na commissies + fees, incl. per-execution).
    public let netPnL: Double
    /// Geplande risk in $ die gebruikt is voor de R-multiple.
    public let riskAmount: Double?
    /// R-multiple (netPnL / riskAmount). `nil` als er geen risk bekend is.
    public let rMultiple: Double?
    /// Categorisch resultaat.
    public let outcome: TradeOutcome
}

/// Aggregatie over een verzameling trades.
public struct TradeStatistics: Equatable, Sendable {
    public let tradeCount: Int
    public let winCount: Int
    public let lossCount: Int
    public let breakevenCount: Int
    public let openCount: Int

    /// Alleen gesloten trades tellen mee.
    public let netPnL: Double
    public let grossPnL: Double
    public let totalCommission: Double
    public let totalFees: Double

    public let winRate: Double
    public let profitFactor: Double?
    public let expectancy: Double
    public let averageWin: Double
    public let averageLoss: Double
    public let averageRMultiple: Double?
    public let largestWin: Double
    public let largestLoss: Double

    /// Maximum drawdown over de equity curve (in $, positief getal).
    public let maxDrawdown: Double
    /// Peak-to-peak drawdown als percentage van piek (0..1).
    public let maxDrawdownPercent: Double

    public let currentStreak: Int
    /// True = huidige streak is winnend, false = verliezend, nil bij 0.
    public let currentStreakIsWinning: Bool?
    public let longestWinStreak: Int
    public let longestLossStreak: Int

    public static let empty = TradeStatistics(
        tradeCount: 0, winCount: 0, lossCount: 0, breakevenCount: 0, openCount: 0,
        netPnL: 0, grossPnL: 0, totalCommission: 0, totalFees: 0,
        winRate: 0, profitFactor: nil, expectancy: 0,
        averageWin: 0, averageLoss: 0, averageRMultiple: nil,
        largestWin: 0, largestLoss: 0,
        maxDrawdown: 0, maxDrawdownPercent: 0,
        currentStreak: 0, currentStreakIsWinning: nil,
        longestWinStreak: 0, longestLossStreak: 0
    )
}

/// Berekeningen voor P&L, R-multiples en samengestelde statistieken.
///
/// Alle publieke methodes zijn puur (geen SwiftData-mutaties), zodat ze
/// makkelijk unit-getest kunnen worden zonder een `ModelContext`.
public struct StatsService: Sendable {

    /// Standaard breakeven-marge in $. Trades met |P&L| ≤ dit bedrag tellen als breakeven.
    public static let breakevenTolerance: Double = 0.005

    public let sessionCalculator: SessionCalculator

    public init(sessionCalculator: SessionCalculator = .default) {
        self.sessionCalculator = sessionCalculator
    }

    // MARK: - Per trade

    /// Berekent metrics voor één trade.
    ///
    /// - Als de trade `executions` heeft, worden bruto P&L en fees per fill
    ///   samengeteld (partial exits).
    /// - Anders wordt de gemiddelde entry/exit-prijs gebruikt in combinatie
    ///   met `quantity`, `tickSize`, `tickValue`.
    public func metrics(for trade: Trade) -> TradeMetrics {
        let (grossPnL, execCommission, execFees, isClosed) = grossAndFees(for: trade)
        let commission = trade.commission + execCommission
        let fees = trade.fees + execFees
        let netPnL = grossPnL - commission - fees

        let riskAmount = self.riskAmount(for: trade)
        let rMultiple: Double? = {
            guard let r = riskAmount, r > 0 else { return nil }
            return netPnL / r
        }()

        let outcome: TradeOutcome
        if !isClosed {
            outcome = .open
        } else if netPnL > Self.breakevenTolerance {
            outcome = .win
        } else if netPnL < -Self.breakevenTolerance {
            outcome = .loss
        } else {
            outcome = .breakeven
        }

        let ticks: Double
        if trade.tickSize > 0 {
            if let exit = trade.exitPrice {
                ticks = (exit - trade.entryPrice) * trade.direction.sign / trade.tickSize
            } else {
                ticks = 0
            }
        } else {
            ticks = 0
        }

        return TradeMetrics(
            signedTicks: ticks,
            grossPnL: grossPnL,
            netPnL: netPnL,
            riskAmount: riskAmount,
            rMultiple: rMultiple,
            outcome: outcome
        )
    }

    /// Geplande risk in $. Wordt afgeleid uit `plannedRisk` (indien gezet)
    /// of anders uit de afstand tussen entry en stop.
    public func riskAmount(for trade: Trade) -> Double? {
        if let planned = trade.plannedRisk, planned > 0 {
            return planned
        }
        guard let stop = trade.stopLoss, trade.tickSize > 0, trade.quantity > 0 else {
            return nil
        }
        let distance = abs(trade.entryPrice - stop)
        guard distance > 0 else { return nil }
        return distance / trade.tickSize * trade.tickValue * trade.quantity
    }

    /// Bruto P&L + opgetelde fees uit executions. Bij afwezigheid van executions
    /// wordt teruggevallen op entry/exit-prijs × quantity.
    private func grossAndFees(for trade: Trade) -> (gross: Double, commission: Double, fees: Double, isClosed: Bool) {
        let direction = trade.direction

        if !trade.executions.isEmpty {
            // Sommeer per fill: teken van signedQuantity bepaalt entry/exit.
            // Bruto P&L = -Σ(signedQuantity × price) mits netto positie = 0
            // (open positie → tel alleen gesloten deel mee).
            let sorted = trade.executions.sorted { $0.date < $1.date }
            var openLots: [(qty: Double, price: Double)] = []  // FIFO
            var realized: Double = 0
            var commissionTotal: Double = 0
            var feesTotal: Double = 0

            for exec in sorted {
                commissionTotal += exec.commission
                feesTotal += exec.fees

                let isEntry = exec.isEntry(for: direction)
                if isEntry {
                    openLots.append((qty: exec.quantity, price: exec.price))
                } else {
                    var remaining = exec.quantity
                    while remaining > 0, !openLots.isEmpty {
                        var lot = openLots[0]
                        let matched = min(remaining, lot.qty)
                        realized += (exec.price - lot.price) * direction.sign * matched * (trade.tickValue / max(trade.tickSize, .leastNonzeroMagnitude))
                        lot.qty -= matched
                        remaining -= matched
                        if lot.qty <= 0 {
                            openLots.removeFirst()
                        } else {
                            openLots[0] = lot
                        }
                    }
                }
            }

            let isClosed = openLots.isEmpty
            return (realized, commissionTotal, feesTotal, isClosed)
        }

        // Geen executions — val terug op gemiddelde entry/exit.
        guard let exit = trade.exitPrice else {
            return (0, 0, 0, false)
        }
        let pointValue = trade.tickSize > 0 ? trade.tickValue / trade.tickSize : 0
        let gross = (exit - trade.entryPrice) * direction.sign * trade.quantity * pointValue
        return (gross, 0, 0, true)
    }

    // MARK: - Aggregatie

    /// Aggregatie over de opgegeven trades. Open trades tellen wel mee in
    /// `openCount` maar niet in P&L of streaks.
    public func statistics(for trades: [Trade]) -> TradeStatistics {
        guard !trades.isEmpty else { return .empty }

        var metricsByTrade: [(trade: Trade, metrics: TradeMetrics)] = []
        metricsByTrade.reserveCapacity(trades.count)
        for t in trades { metricsByTrade.append((t, metrics(for: t))) }

        let openCount = metricsByTrade.filter { $0.metrics.outcome == .open }.count
        let closed = metricsByTrade.filter { $0.metrics.outcome != .open }

        let wins = closed.filter { $0.metrics.outcome == .win }
        let losses = closed.filter { $0.metrics.outcome == .loss }
        let breakevens = closed.filter { $0.metrics.outcome == .breakeven }

        let netPnL = closed.reduce(0) { $0 + $1.metrics.netPnL }
        let grossPnL = closed.reduce(0) { $0 + $1.metrics.grossPnL }

        let totalCommission = closed.reduce(0) { partial, item in
            let execCommission = item.trade.executions.reduce(0) { $0 + $1.commission }
            return partial + item.trade.commission + execCommission
        }
        let totalFees = closed.reduce(0) { partial, item in
            let execFees = item.trade.executions.reduce(0) { $0 + $1.fees }
            return partial + item.trade.fees + execFees
        }

        let winSum = wins.reduce(0) { $0 + $1.metrics.netPnL }
        let lossSum = losses.reduce(0) { $0 + $1.metrics.netPnL }  // negatief

        let winRate: Double = closed.isEmpty ? 0 : Double(wins.count) / Double(closed.count)
        let averageWin = wins.isEmpty ? 0 : winSum / Double(wins.count)
        let averageLoss = losses.isEmpty ? 0 : lossSum / Double(losses.count)

        let profitFactor: Double? = {
            let grossProfit = winSum
            let grossLoss = abs(lossSum)
            guard grossLoss > 0 else { return grossProfit > 0 ? .infinity : nil }
            return grossProfit / grossLoss
        }()

        let expectancy: Double = closed.isEmpty ? 0 : netPnL / Double(closed.count)

        let rMultiples = closed.compactMap { $0.metrics.rMultiple }
        let averageRMultiple: Double? = rMultiples.isEmpty ? nil : rMultiples.reduce(0, +) / Double(rMultiples.count)

        let largestWin = wins.map { $0.metrics.netPnL }.max() ?? 0
        let largestLoss = losses.map { $0.metrics.netPnL }.min() ?? 0

        // Chronologische equity curve voor drawdown & streaks.
        let chronological = closed.sorted { a, b in
            let aDate = a.trade.exitDate ?? a.trade.entryDate
            let bDate = b.trade.exitDate ?? b.trade.entryDate
            return aDate < bDate
        }

        var running: Double = 0
        var peak: Double = 0
        var maxDrawdown: Double = 0
        var maxDrawdownPercent: Double = 0
        for item in chronological {
            running += item.metrics.netPnL
            if running > peak { peak = running }
            let dd = peak - running
            if dd > maxDrawdown { maxDrawdown = dd }
            if peak > 0 {
                let ddPct = dd / peak
                if ddPct > maxDrawdownPercent { maxDrawdownPercent = ddPct }
            }
        }

        var longestWin = 0
        var longestLoss = 0
        var currentWin = 0
        var currentLoss = 0
        var currentStreak = 0
        var currentStreakIsWinning: Bool? = nil

        for item in chronological {
            switch item.metrics.outcome {
            case .win:
                currentWin += 1
                currentLoss = 0
                longestWin = max(longestWin, currentWin)
                currentStreak = currentWin
                currentStreakIsWinning = true
            case .loss:
                currentLoss += 1
                currentWin = 0
                longestLoss = max(longestLoss, currentLoss)
                currentStreak = currentLoss
                currentStreakIsWinning = false
            case .breakeven:
                // Breakeven verbreekt geen streak, maar telt ook niet mee.
                break
            case .open:
                break
            }
        }

        return TradeStatistics(
            tradeCount: trades.count,
            winCount: wins.count,
            lossCount: losses.count,
            breakevenCount: breakevens.count,
            openCount: openCount,
            netPnL: netPnL,
            grossPnL: grossPnL,
            totalCommission: totalCommission,
            totalFees: totalFees,
            winRate: winRate,
            profitFactor: profitFactor,
            expectancy: expectancy,
            averageWin: averageWin,
            averageLoss: averageLoss,
            averageRMultiple: averageRMultiple,
            largestWin: largestWin,
            largestLoss: largestLoss,
            maxDrawdown: maxDrawdown,
            maxDrawdownPercent: maxDrawdownPercent,
            currentStreak: currentStreak,
            currentStreakIsWinning: currentStreakIsWinning,
            longestWinStreak: longestWin,
            longestLossStreak: longestLoss
        )
    }

    // MARK: - Session helpers

    /// Herbereken en zet de sessie op de trade (zonder direct te persisteren).
    public func recomputeSession(for trade: Trade) {
        trade.session = sessionCalculator.session(for: trade.entryDate)
    }

    /// Cumulatieve equity curve op basis van chronologische exit-datums.
    /// Handig voor de dashboard-grafieken (fase 3).
    public func equityCurve(for trades: [Trade], startingBalance: Double = 0) -> [(date: Date, equity: Double)] {
        let closed = trades
            .compactMap { trade -> (Date, Double)? in
                let m = metrics(for: trade)
                guard m.outcome != .open else { return nil }
                let date = trade.exitDate ?? trade.entryDate
                return (date, m.netPnL)
            }
            .sorted { $0.0 < $1.0 }

        var running = startingBalance
        return closed.map { entry in
            running += entry.1
            return (entry.0, running)
        }
    }
}
