import XCTest
@testable import TradeJournal

/// Medailles: catalogus, berekening (ook achteraf, met datum van behalen),
/// voortgang en opslag.
final class MedalServiceTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private var service: MedalService { MedalService(calendar: calendar) }

    /// Maandag 1 juli 2024, 00:00 UTC.
    private let monday = Date(timeIntervalSince1970: 1_719_792_000)

    // MARK: - Helpers

    private func day(_ offset: Int, hour: Int = 15) -> Date {
        monday.addingTimeInterval(TimeInterval(offset * 86_400 + hour * 3_600))
    }

    private func trade(_ outcome: TradeOutcome, on date: Date, pnl: Double? = nil, r: Double? = nil,
                       journal: Bool = false, risk: Bool = false, entry: Date? = nil) -> MedalTradeSnapshot {
        let defaultPnL: Double
        switch outcome {
        case .win: defaultPnL = 100
        case .loss: defaultPnL = -50
        case .breakeven, .open: defaultPnL = 0
        }
        return MedalTradeSnapshot(
            date: date, entryDate: entry ?? date.addingTimeInterval(-600),
            outcome: outcome, netPnL: pnl ?? defaultPnL, rMultiple: r,
            hasJournal: journal, hasRiskPlan: risk
        )
    }

    /// `count` trades, elk op een eigen minuut van dezelfde dag.
    private func trades(_ outcomes: [TradeOutcome], startingAt start: Date? = nil) -> [MedalTradeSnapshot] {
        let base = start ?? day(0)
        return outcomes.enumerated().map { index, outcome in
            trade(outcome, on: base.addingTimeInterval(TimeInterval(index * 60)))
        }
    }

    // MARK: - Catalogus

    func test_catalog_idsUniqueAndTiersComplete() {
        let all = MedalCatalog.all
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "id's moeten uniek zijn")
        for category in MedalCategory.allCases where category != .special {
            XCTAssertEqual(MedalCatalog.definitions(in: category).map(\.tier), MedalTier.allCases, category.rawValue)
        }
        XCTAssertEqual(MedalCatalog.definitions(in: .special).count, 5)
        XCTAssertEqual(MedalTier.standardThresholds, [5, 20, 50, 100, 250, 500, 750, 1000, 2500, 5000])
        XCTAssertEqual(MedalCatalog.definition(withID: "totalTrades.goud")?.rule, .count(100))
        XCTAssertEqual(MedalCatalog.definition(withID: "winStreak.koper")?.rule, .count(3))
    }

    func test_tierOrdering() {
        XCTAssertLessThan(MedalTier.koper, MedalTier.obsidiaan)
        XCTAssertEqual(MedalTier.allCases.map(\.displayName).first, "Koper")
        XCTAssertEqual(MedalTier.allCases.map(\.displayName).last, "Obsidiaan")
    }

    // MARK: - Tellen

    func test_totalTrades_unlocksAtThresholdWithDate() {
        let snapshots = trades(Array(repeating: .win, count: 6))
        let evaluation = service.evaluate(snapshots: snapshots)

        XCTAssertEqual(evaluation.achievedDates["totalTrades.koper"], snapshots[4].date, "datum = 5e trade")
        XCTAssertNil(evaluation.achievedDates["totalTrades.brons"])
        XCTAssertEqual(evaluation.currentValues["totalTrades.brons"], 6)
        let brons = MedalCatalog.definition(withID: "totalTrades.brons")!
        XCTAssertEqual(MedalService.progress(of: brons, in: evaluation), 6.0 / 20.0, accuracy: 0.0001)
        XCTAssertEqual(MedalService.progressText(of: brons, in: evaluation), "6 / 20")
    }

    func test_unorderedInput_isEvaluatedChronologically() {
        let snapshots = trades(Array(repeating: .win, count: 5))
        let evaluation = service.evaluate(snapshots: snapshots.reversed())
        XCTAssertEqual(evaluation.achievedDates["totalTrades.koper"], snapshots[4].date)
    }

    func test_openTrades_countAsLoggedButNotAsWins() {
        let evaluation = service.evaluate(snapshots: trades([.open, .open, .open, .open, .win]))
        XCTAssertNotNil(evaluation.achievedDates["totalTrades.koper"])
        XCTAssertEqual(evaluation.currentValues["winningTrades.koper"], 1)
        XCTAssertEqual(evaluation.closedTradeCount, 1)
    }

    func test_journalingAndRiskManagement() {
        let snapshots = (0..<5).map { index in
            trade(.win, on: day(0).addingTimeInterval(TimeInterval(index * 60)), journal: index < 5, risk: index < 4)
        }
        let evaluation = service.evaluate(snapshots: snapshots)
        XCTAssertNotNil(evaluation.achievedDates["journaling.koper"])
        XCTAssertNil(evaluation.achievedDates["riskManagement.koper"])
        XCTAssertEqual(evaluation.currentValues["riskManagement.koper"], 4)
    }

    func test_totalProfit() {
        let snapshots = (0..<5).map { index in
            trade(.win, on: day(0).addingTimeInterval(TimeInterval(index * 60)), pnl: 120)
        }
        let evaluation = service.evaluate(snapshots: snapshots)
        XCTAssertNotNil(evaluation.achievedDates["totalProfit.koper"], "$600 ≥ $500")
        XCTAssertEqual(evaluation.achievedDates["totalProfit.koper"], snapshots[4].date)
        XCTAssertNil(evaluation.achievedDates["totalProfit.brons"])
    }

    // MARK: - Streaks

    func test_winStreak_longestCountsAndBreakevenDoesNotBreak() {
        let evaluation = service.evaluate(snapshots: trades([.win, .win, .breakeven, .win, .loss, .win]))
        XCTAssertEqual(evaluation.currentValues["winStreak.koper"], 3)
        XCTAssertNotNil(evaluation.achievedDates["winStreak.koper"])
        XCTAssertNil(evaluation.achievedDates["winStreak.brons"])
    }

    func test_activeDays_weekendDoesNotBreakStreak() {
        // Vrijdag, maandag, dinsdag → 3 handelsdagen op rij.
        let snapshots = [trade(.win, on: day(4)), trade(.win, on: day(7)), trade(.win, on: day(8))]
        let evaluation = service.evaluate(snapshots: snapshots)
        XCTAssertEqual(evaluation.currentValues["activeDays.koper"], 3)
        XCTAssertEqual(evaluation.achievedDates["activeDays.koper"], snapshots[2].date)
    }

    func test_activeDays_missedWeekdayBreaksStreak() {
        // Maandag, woensdag, donderdag: dinsdag gemist.
        let snapshots = [trade(.win, on: day(0)), trade(.win, on: day(2)), trade(.win, on: day(3)), trade(.loss, on: day(3, hour: 16))]
        let evaluation = service.evaluate(snapshots: snapshots)
        XCTAssertEqual(evaluation.currentValues["activeDays.koper"], 2)
        XCTAssertNil(evaluation.achievedDates["activeDays.koper"])
    }

    // MARK: - Win rate

    func test_winRate_requiresMinimumTrades() {
        // 8 van 19 = 42%, maar nog geen 20 trades.
        var outcomes: [TradeOutcome] = Array(repeating: .win, count: 8) + Array(repeating: .loss, count: 11)
        var evaluation = service.evaluate(snapshots: trades(outcomes))
        XCTAssertNil(evaluation.achievedDates["winRate.koper"])

        // 20e trade (verlies): 8/20 = 40% → koper.
        outcomes.append(.loss)
        evaluation = service.evaluate(snapshots: trades(outcomes))
        XCTAssertNotNil(evaluation.achievedDates["winRate.koper"])
        XCTAssertEqual(evaluation.currentValues["winRate.koper"] ?? 0, 0.4, accuracy: 0.0001)
    }

    func test_winRate_staysEarnedWhenRateDropsLater() {
        let outcomes: [TradeOutcome] = Array(repeating: .win, count: 20) + Array(repeating: .loss, count: 40)
        let evaluation = service.evaluate(snapshots: trades(outcomes))
        XCTAssertNotNil(evaluation.achievedDates["winRate.koper"])
        XCTAssertLessThan(evaluation.currentValues["winRate.koper"] ?? 1, 0.4)
    }

    func test_winRate_progressUsesTradesAndRate() {
        let evaluation = service.evaluate(snapshots: trades(Array(repeating: .win, count: 10)))
        let koper = MedalCatalog.definition(withID: "winRate.koper")!
        XCTAssertEqual(MedalService.progress(of: koper, in: evaluation), 0.5, accuracy: 0.0001, "10/20 trades")
        XCTAssertEqual(MedalService.progressText(of: koper, in: evaluation), "100% / 40% · 10/20 trades")
    }

    // MARK: - Speciaal

    func test_firstTrade() {
        let evaluation = service.evaluate(snapshots: trades([.open]))
        XCTAssertNotNil(evaluation.achievedDates["special.firstTrade"])
        XCTAssertTrue(service.evaluate(snapshots: []).achievedDates.isEmpty)
    }

    func test_comeback_afterThreeLosses() {
        XCTAssertNotNil(service.evaluate(snapshots: trades([.loss, .loss, .loss, .win])).achievedDates["special.comeback"])
        XCTAssertNil(service.evaluate(snapshots: trades([.loss, .loss, .win])).achievedDates["special.comeback"])
        XCTAssertNil(service.evaluate(snapshots: trades([.loss, .loss, .loss, .loss])).achievedDates["special.comeback"])
    }

    func test_nightOwl() {
        let late = trade(.win, on: day(1, hour: 23), entry: day(1, hour: 22) + 1800)
        XCTAssertNotNil(service.evaluate(snapshots: [late]).achievedDates["special.nightOwl"])
        let early = trade(.win, on: day(1, hour: 5), entry: day(1, hour: 4))
        XCTAssertNotNil(service.evaluate(snapshots: [early]).achievedDates["special.nightOwl"])
        let normal = trade(.win, on: day(1, hour: 15), entry: day(1, hour: 14))
        XCTAssertNil(service.evaluate(snapshots: [normal]).achievedDates["special.nightOwl"])
    }

    func test_perfectWeek() {
        let perfect = (0..<5).map { trade(.win, on: day($0)) } + [trade(.breakeven, on: day(4, hour: 16))]
        let evaluation = service.evaluate(snapshots: perfect)
        XCTAssertEqual(evaluation.achievedDates["special.perfectWeek"], perfect.last?.date)

        let withLoss = (0..<5).map { trade(.win, on: day($0)) } + [trade(.loss, on: day(4, hour: 16))]
        XCTAssertNil(service.evaluate(snapshots: withLoss).achievedDates["special.perfectWeek"])

        let tooFew = (0..<4).map { trade(.win, on: day($0)) }
        XCTAssertNil(service.evaluate(snapshots: tooFew).achievedDates["special.perfectWeek"])
    }

    func test_homeRun() {
        XCTAssertNotNil(service.evaluate(snapshots: [trade(.win, on: day(0), r: 5.2)]).achievedDates["special.homeRun"])
        XCTAssertNil(service.evaluate(snapshots: [trade(.win, on: day(0), r: 4.9)]).achievedDates["special.homeRun"])
    }

    // MARK: - Opslag

    func test_store_recordsOnlyNewAndKeepsOriginalDate() {
        let suite = "MedalStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MedalStore(defaults: defaults)
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(Set(store.record(["a": first, "b": first])), ["a", "b"])
        XCTAssertEqual(store.record(["a": Date(), "c": first]), ["c"])
        XCTAssertEqual(store.unlocked["a"], first)

        let restarted = MedalStore(defaults: defaults)
        XCTAssertEqual(restarted.unlocked.count, 3)
        XCTAssertEqual(restarted.unlocked["a"]?.timeIntervalSince1970 ?? 0, first.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertFalse(restarted.hasCompletedInitialSync)
        restarted.markInitialSyncDone()
        XCTAssertTrue(MedalStore(defaults: defaults).hasCompletedInitialSync)
    }

    func test_medalAndRewardKeys_areBackedUp() {
        for key in [MedalStore.Keys.unlocked, MedalStore.Keys.initialSyncDone,
                    RewardSettings.Keys.animationsEnabled, RewardSettings.Keys.medalNotificationsEnabled,
                    RewardSettings.Keys.openReportsAfterSave] {
            XCTAssertTrue(SettingsMigrator.backedUpKeys.contains(key), key)
        }
    }
}
