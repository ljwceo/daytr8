import XCTest
@testable import TradeJournal

final class TradingScoreServiceTests: XCTestCase {

    private let service = TradingScoreService()

    private func makeStatistics(
        winRate: Double = 0,
        profitFactor: Double? = nil,
        averageWin: Double = 0,
        averageLoss: Double = 0,
        maxDrawdownPercent: Double = 0
    ) -> TradeStatistics {
        TradeStatistics(
            tradeCount: 10, winCount: 5, lossCount: 5, breakevenCount: 0, openCount: 0,
            netPnL: 0, grossPnL: 0, totalCommission: 0, totalFees: 0,
            winRate: winRate, profitFactor: profitFactor, expectancy: 0,
            averageWin: averageWin, averageLoss: averageLoss, averageRMultiple: nil,
            largestWin: 0, largestLoss: 0,
            maxDrawdown: 0, maxDrawdownPercent: maxDrawdownPercent,
            currentStreak: 0, currentStreakIsWinning: nil,
            longestWinStreak: 0, longestLossStreak: 0
        )
    }

    func test_winRateScore_scalesLinearlyTo100() {
        let stats = makeStatistics(winRate: 0.5)
        let score = service.score(for: stats, dailyNetPnL: [], ruleAdherenceRate: nil)
        XCTAssertEqual(score.winRate, 50, accuracy: 0.01)
    }

    func test_profitFactorScore_capsAt100_andHandlesInfiniteAndNil() {
        let noLosses = service.score(for: makeStatistics(profitFactor: .infinity), dailyNetPnL: [], ruleAdherenceRate: nil)
        XCTAssertEqual(noLosses.profitFactor, 100)

        let pf3 = service.score(for: makeStatistics(profitFactor: 3.0), dailyNetPnL: [], ruleAdherenceRate: nil)
        XCTAssertEqual(pf3.profitFactor, 100, accuracy: 0.01)

        let pf1_5 = service.score(for: makeStatistics(profitFactor: 1.5), dailyNetPnL: [], ruleAdherenceRate: nil)
        XCTAssertEqual(pf1_5.profitFactor, 50, accuracy: 0.01)

        let noTrades = service.score(for: makeStatistics(profitFactor: nil), dailyNetPnL: [], ruleAdherenceRate: nil)
        XCTAssertEqual(noTrades.profitFactor, 0)
    }

    func test_avgWinLossScore_ratioOf3IsPerfect() {
        let stats = makeStatistics(averageWin: 300, averageLoss: -100)
        let score = service.score(for: stats, dailyNetPnL: [], ruleAdherenceRate: nil)
        XCTAssertEqual(score.avgWinLossRatio, 100, accuracy: 0.01)
    }

    func test_drawdownScore_isInverseOfDrawdownPercent() {
        let stats = makeStatistics(maxDrawdownPercent: 0.25)
        let score = service.score(for: stats, dailyNetPnL: [], ruleAdherenceRate: nil)
        XCTAssertEqual(score.drawdown, 75, accuracy: 0.01)
    }

    func test_consistencyScore_isHighWhenProfitIsSpreadEvenly() {
        let stats = makeStatistics()
        let evenlySpread = service.score(for: stats, dailyNetPnL: [100, 100, 100, 100], ruleAdherenceRate: nil)
        XCTAssertEqual(evenlySpread.consistency, 100, accuracy: 0.01)
    }

    func test_consistencyScore_isPenalizedWhenOneDayDominates() {
        let stats = makeStatistics()
        let dominated = service.score(for: stats, dailyNetPnL: [1000, 10, 10, 10], ruleAdherenceRate: nil)
        XCTAssertLessThan(dominated.consistency, 50)
    }

    func test_consistencyScore_isZeroWithNoProfitableDays() {
        let stats = makeStatistics()
        let allLosses = service.score(for: stats, dailyNetPnL: [-100, -50], ruleAdherenceRate: nil)
        XCTAssertEqual(allLosses.consistency, 0)
    }

    func test_ruleAdherenceScore_reflectsRate_andDefaultsToZeroWhenNil() {
        let stats = makeStatistics()
        let half = service.score(for: stats, dailyNetPnL: [], ruleAdherenceRate: 0.5)
        XCTAssertEqual(half.ruleAdherence, 50, accuracy: 0.01)

        let none = service.score(for: stats, dailyNetPnL: [], ruleAdherenceRate: nil)
        XCTAssertEqual(none.ruleAdherence, 0)
    }

    func test_overall_isAverageOfSixAxes() {
        let score = TradingScore(winRate: 100, profitFactor: 100, avgWinLossRatio: 100, consistency: 100, drawdown: 100, ruleAdherence: 100)
        XCTAssertEqual(score.overall, 100, accuracy: 0.01)

        let mixed = TradingScore(winRate: 0, profitFactor: 0, avgWinLossRatio: 0, consistency: 0, drawdown: 0, ruleAdherence: 60)
        XCTAssertEqual(mixed.overall, 10, accuracy: 0.01)
    }

    func test_axes_exposesAllSixLabelsInOrder() {
        let score = TradingScore(winRate: 1, profitFactor: 2, avgWinLossRatio: 3, consistency: 4, drawdown: 5, ruleAdherence: 6)
        XCTAssertEqual(score.axes.map(\.score), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(score.axes.count, 6)
    }
}
