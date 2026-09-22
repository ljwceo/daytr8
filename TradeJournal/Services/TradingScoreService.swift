import Foundation

/// Eén as van de trading-score radar-chart.
public struct TradingScoreAxis: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    /// 0...100.
    public let score: Double
}

/// Samengestelde trading-score (vergelijkbaar met de Zella Score): zes assen
/// van 0-100 plus een gemiddelde. Gebruikt door de radar-chart op het dashboard.
public struct TradingScore: Equatable, Sendable {
    public let winRate: Double
    public let profitFactor: Double
    public let avgWinLossRatio: Double
    public let consistency: Double
    public let drawdown: Double
    public let ruleAdherence: Double

    public var overall: Double {
        (winRate + profitFactor + avgWinLossRatio + consistency + drawdown + ruleAdherence) / 6
    }

    public var axes: [TradingScoreAxis] {
        [
            TradingScoreAxis(id: "winRate", label: "Win rate", score: winRate),
            TradingScoreAxis(id: "profitFactor", label: "Profit factor", score: profitFactor),
            TradingScoreAxis(id: "avgWinLoss", label: "Avg win/loss", score: avgWinLossRatio),
            TradingScoreAxis(id: "consistency", label: "Consistentie", score: consistency),
            TradingScoreAxis(id: "drawdown", label: "Drawdown", score: drawdown),
            TradingScoreAxis(id: "ruleAdherence", label: "Regels gevolgd", score: ruleAdherence)
        ]
    }

    public static let empty = TradingScore(winRate: 0, profitFactor: 0, avgWinLossRatio: 0, consistency: 0, drawdown: 100, ruleAdherence: 0)
}

/// Berekent de samengestelde trading-score uit `TradeStatistics`.
///
/// Er bestaat geen gepubliceerde formule voor TradeZella's eigen "Zella Score",
/// dus elke as hieronder is een eigen, expliciet gekozen 0-100 normalisatie met
/// een plafond ruim boven wat in daytrading realistisch haalbaar is (bijv. een
/// profit factor van 3 telt al als 100). Dat maakt de score een relatieve
/// vergelijkingsmaat tussen periodes, geen absolute waarheid.
public struct TradingScoreService: Sendable {

    public init() {}

    public func score(for statistics: TradeStatistics, dailyNetPnL: [Double], ruleAdherenceRate: Double?) -> TradingScore {
        let winRateScore = min(max(statistics.winRate, 0), 1) * 100

        let profitFactorScore: Double = {
            guard let pf = statistics.profitFactor else { return 0 }
            if pf.isInfinite { return 100 }
            return min(max(pf, 0) / 3.0, 1) * 100
        }()

        let avgWinLossScore: Double = {
            guard statistics.averageLoss != 0 else { return statistics.averageWin > 0 ? 100 : 0 }
            let ratio = statistics.averageWin / abs(statistics.averageLoss)
            return min(max(ratio, 0) / 3.0, 1) * 100
        }()

        let drawdownScore = (1 - min(max(statistics.maxDrawdownPercent, 0), 1)) * 100

        let consistencyScore = consistency(fromDailyNetPnL: dailyNetPnL)

        let ruleAdherenceScore = (ruleAdherenceRate.map { min(max($0, 0), 1) } ?? 0) * 100

        return TradingScore(
            winRate: winRateScore,
            profitFactor: profitFactorScore,
            avgWinLossRatio: avgWinLossScore,
            consistency: consistencyScore,
            drawdown: drawdownScore,
            ruleAdherence: ruleAdherenceScore
        )
    }

    /// Consistentie: hoe groter het aandeel van de beste dag in de totale winst,
    /// hoe meer de resultaten op één uitschieter leunen. Boven 40% aandeel wordt
    /// dat bestraft; bij 100% (alle winst op één dag) is de score 0.
    private func consistency(fromDailyNetPnL dailyNetPnL: [Double]) -> Double {
        guard !dailyNetPnL.isEmpty else { return 0 }
        let profitableDays = dailyNetPnL.filter { $0 > 0 }
        let totalProfit = profitableDays.reduce(0, +)
        guard totalProfit > 0, let bestDay = profitableDays.max() else { return 0 }
        let bestDayShare = bestDay / totalProfit
        let penalty = max(0, bestDayShare - 0.4) * (100.0 / 0.6)
        return max(0, 100 - penalty)
    }
}
