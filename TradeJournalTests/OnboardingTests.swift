import XCTest
@testable import TradeJournal

/// Welkomstmelding en rondleiding: eerste start toont de melding, tweede
/// start niet, "Rondleiding opnieuw bekijken" werkt, en de afsluitknoppen
/// sturen naar het dashboard of een nieuwe trade.
final class OnboardingTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// Nieuwe viewmodel + settings op dezelfde defaults = een app-(her)start.
    private func launch() -> OnboardingViewModel {
        let viewModel = OnboardingViewModel(settings: OnboardingSettings(defaults: defaults))
        viewModel.handleLaunch()
        return viewModel
    }

    func test_firstLaunch_showsBanner_secondLaunchDoesNot() {
        XCTAssertFalse(OnboardingSettings(defaults: defaults).hasSeenOnboarding)

        let first = launch()
        XCTAssertTrue(first.isBannerVisible)
        XCTAssertTrue(OnboardingSettings(defaults: defaults).hasSeenOnboarding)

        let second = launch()
        XCTAssertFalse(second.isBannerVisible)
        XCTAssertFalse(second.isTourPresented)
    }

    func test_dismissBanner_doesNotStartTour_andStaysHiddenAfterRestart() {
        let viewModel = launch()
        viewModel.dismissBanner()
        XCTAssertFalse(viewModel.isBannerVisible)
        XCTAssertFalse(viewModel.isTourPresented)
        XCTAssertFalse(launch().isBannerVisible)
    }

    func test_tapBanner_opensTourAtFirstStep() {
        let viewModel = launch()
        viewModel.openTourFromBanner()
        XCTAssertFalse(viewModel.isBannerVisible)
        XCTAssertTrue(viewModel.isTourPresented)
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func test_replayFromSettings_restartsAtFirstStep() {
        let viewModel = launch()
        viewModel.dismissBanner()

        viewModel.startTour()
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .confluences)
        viewModel.skipTour()
        viewModel.tourDidDismiss()
        XCTAssertFalse(viewModel.isTourPresented)

        // Meer → Rondleiding opnieuw bekijken
        viewModel.startTour()
        XCTAssertTrue(viewModel.isTourPresented)
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func test_settingsReset_showsBannerAgainOnNextLaunch() {
        _ = launch()
        OnboardingSettings(defaults: defaults).reset()
        XCTAssertTrue(launch().isBannerVisible)
    }

    func test_steps_nextStopsAtLastStep() {
        let viewModel = launch()
        viewModel.startTour()
        for _ in 0..<(OnboardingStep.allCases.count + 2) {
            viewModel.goToNextStep()
        }
        XCTAssertEqual(viewModel.currentStep, .done)
        XCTAssertTrue(viewModel.currentStep.isLast)
        XCTAssertEqual(OnboardingStep.allCases.count, 7)
    }

    func test_finish_toDashboard_selectsDashboardTab() {
        let viewModel = launch()
        viewModel.selectedTab = .more
        viewModel.startTour()
        viewModel.finish(.dashboard)
        XCTAssertFalse(viewModel.isTourPresented)
        viewModel.tourDidDismiss()
        XCTAssertEqual(viewModel.selectedTab, .dashboard)
        XCTAssertFalse(viewModel.consumeNewTradeRequest())
    }

    func test_finish_firstTrade_opensTradesTabAndRequestsFormOnce() {
        let viewModel = launch()
        viewModel.startTour()
        viewModel.finish(.firstTrade)
        // Pas na de sluitanimatie van de rondleiding.
        XCTAssertFalse(viewModel.isNewTradeRequested)
        viewModel.tourDidDismiss()
        XCTAssertEqual(viewModel.selectedTab, .trades)
        XCTAssertTrue(viewModel.consumeNewTradeRequest())
        XCTAssertFalse(viewModel.consumeNewTradeRequest())
    }

    func test_skip_keepsCurrentTab() {
        let viewModel = launch()
        viewModel.selectedTab = .reports
        viewModel.startTour()
        viewModel.skipTour()
        viewModel.tourDidDismiss()
        XCTAssertEqual(viewModel.selectedTab, .reports)
    }

    func test_navigationStep_coversAllTabs() {
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Dashboard", "Kalender", "Trades", "Rapporten", "Meer"])
        for tab in AppTab.allCases {
            XCTAssertFalse(tab.onboardingDescription.isEmpty)
        }
    }
}
