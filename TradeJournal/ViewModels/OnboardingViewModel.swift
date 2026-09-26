import Foundation
import Observation

/// Coördineert de welkomstmelding, de onboarding-rondleiding en waar de
/// gebruiker daarna naartoe gaat (dashboard of een nieuwe trade).
///
/// Leeft op app-niveau en wordt via de environment gedeeld met `RootTabView`,
/// `TradesView` en `MoreView`.
@Observable
final class OnboardingViewModel {

    /// Waar de rondleiding naartoe leidt als hij sluit.
    enum Destination: Equatable {
        case stay
        case dashboard
        case firstTrade
    }

    /// Geselecteerde tab in `RootTabView`.
    var selectedTab: AppTab = .dashboard

    private(set) var isBannerVisible = false
    var isTourPresented = false
    var currentStep: OnboardingStep = .welcome

    /// `TradesView` opent het tradeformulier zodra dit `true` is.
    private(set) var isNewTradeRequested = false

    @ObservationIgnored private var pendingDestination: Destination = .stay
    @ObservationIgnored private let settings: OnboardingSettings

    init(settings: OnboardingSettings = OnboardingSettings()) {
        self.settings = settings
    }

    // MARK: - Welkomstmelding

    /// Aanroepen bij de app-start (na ontgrendelen). Toont de melding alleen
    /// bij de allereerste start en markeert hem meteen als gezien, zodat een
    /// tweede start hem niet opnieuw toont.
    func handleLaunch() {
        guard settings.shouldShowWelcomeBanner else { return }
        settings.hasSeenOnboarding = true
        isBannerVisible = true
    }

    func dismissBanner() {
        isBannerVisible = false
    }

    func openTourFromBanner() {
        isBannerVisible = false
        startTour()
    }

    // MARK: - Rondleiding

    /// Start de rondleiding vanaf stap 1 (ook via Meer → Rondleiding opnieuw bekijken).
    func startTour() {
        isBannerVisible = false
        currentStep = .welcome
        pendingDestination = .stay
        isTourPresented = true
    }

    func goToNextStep() {
        if let next = currentStep.next {
            currentStep = next
        }
    }

    func skipTour() {
        finish(.stay)
    }

    /// Sluit de rondleiding; de bestemming wordt toegepast in `tourDidDismiss`
    /// (na de sluitanimatie, zodat een sheet niet botst met de full-screen cover).
    func finish(_ destination: Destination) {
        pendingDestination = destination
        isTourPresented = false
    }

    func tourDidDismiss() {
        switch pendingDestination {
        case .stay:
            break
        case .dashboard:
            selectedTab = .dashboard
        case .firstTrade:
            selectedTab = .trades
            isNewTradeRequested = true
        }
        pendingDestination = .stay
    }

    /// Geeft `true` (één keer) als er een nieuwe trade gevraagd is.
    func consumeNewTradeRequest() -> Bool {
        guard isNewTradeRequested else { return false }
        isNewTradeRequested = false
        return true
    }
}
