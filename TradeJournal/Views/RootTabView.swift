import SwiftUI

/// Hoofdnavigatie met de vijf top-level tabs (`AppTab`).
///
/// Toont bij de eerste start de welkomstmelding bovenin en presenteert de
/// onboarding-rondleiding. Past ook het color scheme en de tint van het
/// actieve thema toe (dit is de root view).
struct RootTabView: View {

    @Environment(OnboardingViewModel.self) private var onboarding
    @Environment(AppLockViewModel.self) private var appLock

    /// Hoe lang de welkomstmelding blijft staan voordat hij vanzelf verdwijnt.
    private let bannerDuration: Duration = .seconds(10)

    private var isBannerShowing: Bool {
        onboarding.isBannerVisible && !appLock.isLocked
    }

    var body: some View {
        @Bindable var onboarding = onboarding

        TabView(selection: $onboarding.selectedTab) {
            DashboardView()
                .tabItem { tabLabel(.dashboard) }
                .tag(AppTab.dashboard)

            CalendarView()
                .tabItem { tabLabel(.calendar) }
                .tag(AppTab.calendar)

            TradesView()
                .tabItem { tabLabel(.trades) }
                .tag(AppTab.trades)

            ReportsView()
                .tabItem { tabLabel(.reports) }
                .tag(AppTab.reports)

            MoreView()
                .tabItem { tabLabel(.more) }
                .tag(AppTab.more)
        }
        .background(Theme.background)
        .overlay(alignment: .top) {
            if isBannerShowing {
                WelcomeBannerView(
                    onOpen: { onboarding.openTourFromBanner() },
                    onDismiss: { onboarding.dismissBanner() }
                )
                .padding(.horizontal, Theme.cardPadding)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isBannerShowing)
        .task(id: isBannerShowing) {
            // Net als een pushmelding verdwijnt de melding na een poosje vanzelf;
            // de rondleiding blijft te vinden via Meer.
            guard isBannerShowing else { return }
            try? await Task.sleep(for: bannerDuration)
            if !Task.isCancelled {
                onboarding.dismissBanner()
            }
        }
        .fullScreenCover(isPresented: $onboarding.isTourPresented, onDismiss: {
            onboarding.tourDidDismiss()
        }) {
            OnboardingView()
                .environment(onboarding)
        }
        .preferredColorScheme(Theme.colorScheme)
        .tint(Theme.accent)
    }

    private func tabLabel(_ tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }
}

#Preview {
    RootTabView()
        .environment(AppLockViewModel())
        .environment(OnboardingViewModel())
}
