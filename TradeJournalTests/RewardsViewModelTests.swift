import XCTest
import SwiftData
@testable import TradeJournal

/// Rewards-flow: stille eerste berekening met samenvatting, meldingen na het
/// opslaan, hot streak, doorsturen naar Rapporten en de instellingen.
@MainActor
final class RewardsViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        suiteName = "RewardsViewModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeViewModel() -> RewardsViewModel {
        RewardsViewModel(store: MedalStore(defaults: defaults), settings: RewardSettings(defaults: defaults))
    }

    private var nextDate = Date(timeIntervalSince1970: 1_719_842_400)  // ma 1 juli 2024, 14:00 UTC

    @discardableResult
    private func addTrade(win: Bool) -> Trade {
        nextDate = nextDate.addingTimeInterval(600)
        let trade = Trade(
            symbol: "NQ", direction: .long,
            entryDate: nextDate, exitDate: nextDate.addingTimeInterval(300),
            entryPrice: 100, exitPrice: win ? 101 : 99, quantity: 1,
            tickSize: 1, tickValue: 10
        )
        context.insert(trade)
        return trade
    }

    // MARK: - Eerste berekening

    func test_initialSync_awardsSilentlyWithOneSummary() {
        for _ in 0..<6 { addTrade(win: true) }
        let viewModel = makeViewModel()
        viewModel.sync(in: context)

        XCTAssertTrue(viewModel.store.hasCompletedInitialSync)
        XCTAssertTrue(viewModel.store.isUnlocked("totalTrades.koper"))
        XCTAssertTrue(viewModel.store.isUnlocked("winStreak.brons"), "6 op rij ≥ 5")
        guard case .summary(let count, true) = viewModel.currentToast else {
            return XCTFail("verwacht één samenvatting, kreeg \(String(describing: viewModel.currentToast))")
        }
        XCTAssertEqual(count, viewModel.unlockedCount)

        // Na de samenvatting geen losse meldingen meer in de wachtrij.
        viewModel.dismissToast()
        XCTAssertNil(viewModel.currentToast)
    }

    func test_initialSync_withoutTrades_showsNothing() {
        let viewModel = makeViewModel()
        viewModel.sync(in: context)
        XCTAssertTrue(viewModel.store.hasCompletedInitialSync)
        XCTAssertNil(viewModel.currentToast)
    }

    // MARK: - Na opslaan

    func test_tradeSaved_showsCelebrationThenMedalToast() {
        let viewModel = makeViewModel()
        viewModel.sync(in: context)  // eerste (lege) berekening

        let trade = addTrade(win: true)
        viewModel.tradeSaved(trade, isNew: true, in: context)

        XCTAssertNotNil(viewModel.celebration)
        XCTAssertEqual(viewModel.celebration?.outcome, .win)
        XCTAssertEqual(viewModel.celebration?.winStreak, 1)
        XCTAssertEqual(viewModel.celebration?.isHotStreak, false)
        XCTAssertNil(viewModel.currentToast, "melding wacht tot de animatie klaar is")

        viewModel.finishCelebration()
        XCTAssertNil(viewModel.celebration)
        XCTAssertEqual(viewModel.requestedTab, .reports)
        guard case .medal(let definition, _) = viewModel.currentToast else {
            return XCTFail("verwacht een medaillemelding")
        }
        XCTAssertEqual(definition.id, "special.firstTrade")
    }

    func test_hotStreak_fromThreeWinsInARow() {
        let viewModel = makeViewModel()
        viewModel.sync(in: context)
        addTrade(win: false)
        addTrade(win: true)
        addTrade(win: true)
        let third = addTrade(win: true)
        viewModel.tradeSaved(third, isNew: true, in: context)

        XCTAssertEqual(viewModel.celebration?.winStreak, 3)
        XCTAssertEqual(viewModel.celebration?.isHotStreak, true)
        XCTAssertEqual(viewModel.celebration?.intensity ?? -1, 0, accuracy: 0.0001)
    }

    func test_hotStreakIntensity_growsAndCaps() {
        let short = RewardsViewModel.Celebration(outcome: .win, netPnL: 1, currency: "USD", winStreak: 5)
        let long = RewardsViewModel.Celebration(outcome: .win, netPnL: 1, currency: "USD", winStreak: 30)
        XCTAssertGreaterThan(short.intensity, 0)
        XCTAssertGreaterThan(long.intensity, short.intensity)
        XCTAssertEqual(long.intensity, 1)
        XCTAssertEqual(RewardsViewModel.Celebration(outcome: .win, netPnL: 1, currency: "USD", winStreak: 2).intensity, 0)
    }

    func test_losingTrade_noHotStreak() {
        let viewModel = makeViewModel()
        viewModel.sync(in: context)
        for _ in 0..<3 { addTrade(win: true) }
        let loss = addTrade(win: false)
        viewModel.tradeSaved(loss, isNew: true, in: context)
        XCTAssertEqual(viewModel.celebration?.winStreak, 0)
        XCTAssertEqual(viewModel.celebration?.isHotStreak, false)
    }

    func test_editingTrade_noCelebrationNoRedirect() {
        let viewModel = makeViewModel()
        viewModel.sync(in: context)
        let trade = addTrade(win: true)
        viewModel.tradeSaved(trade, isNew: false, in: context)
        XCTAssertNil(viewModel.celebration)
        XCTAssertNil(viewModel.requestedTab)
        XCTAssertTrue(viewModel.store.isUnlocked("special.firstTrade"), "medailles tellen wel")
    }

    // MARK: - Instellingen

    func test_animationsOff_redirectsDirectly() {
        RewardSettings(defaults: defaults).animationsEnabled = false
        let viewModel = makeViewModel()
        viewModel.sync(in: context)
        let trade = addTrade(win: true)
        viewModel.tradeSaved(trade, isNew: true, in: context)
        XCTAssertNil(viewModel.celebration)
        XCTAssertEqual(viewModel.requestedTab, .reports)
        XCTAssertNotNil(viewModel.currentToast)
    }

    func test_redirectOff_staysOnCurrentTab() {
        RewardSettings(defaults: defaults).openReportsAfterSave = false
        let viewModel = makeViewModel()
        viewModel.sync(in: context)
        let trade = addTrade(win: true)
        viewModel.tradeSaved(trade, isNew: true, in: context)
        viewModel.finishCelebration()
        XCTAssertNil(viewModel.requestedTab)
    }

    func test_notificationsOff_recordsWithoutToast() {
        RewardSettings(defaults: defaults).medalNotificationsEnabled = false
        let viewModel = makeViewModel()
        viewModel.sync(in: context)
        let trade = addTrade(win: true)
        viewModel.tradeSaved(trade, isNew: true, in: context)
        viewModel.finishCelebration()
        XCTAssertNil(viewModel.currentToast)
        XCTAssertTrue(viewModel.store.isUnlocked("special.firstTrade"))
    }

    func test_manyNewMedalsAtOnce_becomeOneSummary() {
        let viewModel = makeViewModel()
        viewModel.sync(in: context)  // eerste (lege) berekening

        // Bijv. na een CSV-import: veel trades tegelijk.
        for _ in 0..<25 { addTrade(win: true) }
        viewModel.sync(in: context)
        guard case .summary(let count, false) = viewModel.currentToast else {
            return XCTFail("verwacht een samenvatting")
        }
        XCTAssertGreaterThan(count, RewardsViewModel.maximumIndividualToasts)
    }

    func test_openToast_opensOverviewWithHighlight() {
        let viewModel = makeViewModel()
        viewModel.sync(in: context)
        let trade = addTrade(win: true)
        viewModel.tradeSaved(trade, isNew: false, in: context)
        XCTAssertNotNil(viewModel.currentToast)

        viewModel.openToast()
        XCTAssertTrue(viewModel.isOverviewPresented)
        XCTAssertEqual(viewModel.highlightedMedalID, "special.firstTrade")
        XCTAssertNil(viewModel.currentToast)
    }

    func test_settingsDefaults() {
        let settings = RewardSettings(defaults: defaults)
        XCTAssertTrue(settings.animationsEnabled)
        XCTAssertTrue(settings.medalNotificationsEnabled)
        XCTAssertTrue(settings.openReportsAfterSave)
    }
}
