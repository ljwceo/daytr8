import SwiftUI

/// Hoofdnavigatie met de vijf top-level tabs (`AppTab`).
///
/// Toont bij de eerste start de welkomstmelding bovenin en presenteert de
/// onboarding-rondleiding. Past ook het color scheme en de tint van het
/// actieve thema toe (dit is de root view).
///
/// Toont ook een backup die via Bestanden of het deelmenu binnenkomt
/// (`IncomingFileRouter`) als sheet — pas nadat het app-slot ontgrendeld is.
struct RootTabView: View {

    @Environment(OnboardingViewModel.self) private var onboarding
    @Environment(AppLockViewModel.self) private var appLock
    @Environment(IncomingFileRouter.self) private var incomingFiles
    @Environment(RewardsViewModel.self) private var rewards

    /// De binnengekomen backup die nu als sheet getoond wordt.
    @State private var incomingBackup: IncomingBackup?
    /// Bestand van de laatst getoonde sheet, om na het sluiten op te ruimen.
    @State private var shownBackupURL: URL?
    /// Gezet als de sheet sluit omdat de app vergrendelt: na ontgrendelen
    /// wordt hij opnieuw getoond (en het bestand dus nog niet opgeruimd).
    @State private var backupURLToReshow: URL?

    /// Hoe lang de welkomstmelding blijft staan voordat hij vanzelf verdwijnt.
    private let bannerDuration: Duration = .seconds(10)

    private var isBannerShowing: Bool {
        onboarding.isBannerVisible && !appLock.isLocked
    }

    var body: some View {
        @Bindable var onboarding = onboarding
        @Bindable var rewards = rewards

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
        // Animatie na het opslaan van een trade (tik = overslaan).
        .overlay {
            if let celebration = rewards.celebration, !appLock.isLocked {
                TradeSavedCelebrationView(celebration: celebration) {
                    withAnimation(.easeOut(duration: 0.25)) { rewards.finishCelebration() }
                }
                .id(celebration.id)
                .transition(.opacity)
            }
        }
        // Medaillemeldingen, één voor één.
        .overlay(alignment: .top) {
            if let toast = rewards.currentToast, !appLock.isLocked, !isBannerShowing {
                MedalToastView(
                    toast: toast,
                    onOpen: { rewards.openToast() },
                    onDismiss: { withAnimation(.easeInOut(duration: 0.3)) { rewards.dismissToast() } }
                )
                .id(toast.id)
                .padding(.horizontal, Theme.cardPadding)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: rewards.currentToast?.id)
        .task(id: rewards.currentToast?.id) {
            guard rewards.currentToast != nil else { return }
            try? await Task.sleep(for: RewardsViewModel.toastDuration)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.3)) { rewards.dismissToast() }
            }
        }
        .onChange(of: rewards.requestedTab) { _, tab in
            guard let tab else { return }
            onboarding.selectedTab = tab
            rewards.requestedTab = nil
        }
        .sheet(isPresented: $rewards.isOverviewPresented) {
            NavigationStack {
                MedalsView(showsCloseButton: true)
            }
            .environment(rewards)
        }
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
        .sheet(item: $incomingBackup, onDismiss: incomingBackupDismissed) { backup in
            NavigationStack {
                IncomingBackupView(url: backup.url)
            }
        }
        .onAppear { presentIncomingBackupIfPossible() }
        .onChange(of: incomingFiles.pendingURL) { presentIncomingBackupIfPossible() }
        .onChange(of: onboarding.isTourPresented) { presentIncomingBackupIfPossible() }
        .onChange(of: appLock.isLocked) { _, isLocked in
            if isLocked, let backup = incomingBackup {
                // Niet over het slot heen tonen: sluiten en na ontgrendelen terug.
                backupURLToReshow = backup.url
                incomingBackup = nil
            } else {
                presentIncomingBackupIfPossible()
            }
        }
        .preferredColorScheme(Theme.colorScheme)
        .tint(Theme.accent)
    }

    // MARK: - Binnenkomende backup

    private func presentIncomingBackupIfPossible() {
        // Eén presentatie tegelijk: niet naast de rondleiding (fullScreenCover).
        guard incomingBackup == nil, !appLock.isLocked, !onboarding.isTourPresented,
              let url = incomingFiles.consume() else { return }
        shownBackupURL = url
        incomingBackup = IncomingBackup(url: url)
    }

    private func incomingBackupDismissed() {
        if let url = backupURLToReshow {
            backupURLToReshow = nil
            incomingFiles.receive(url)
        } else if let url = shownBackupURL {
            // Klaar (hersteld of geannuleerd): de Inbox-kopie mag weg.
            incomingFiles.discard(url)
        }
        shownBackupURL = nil
        presentIncomingBackupIfPossible()
    }

    private func tabLabel(_ tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }
}

/// Item voor `.sheet(item:)`: elke binnenkomende backup is een nieuwe sheet.
private struct IncomingBackup: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    RootTabView()
        .environment(AppLockViewModel())
        .environment(OnboardingViewModel())
        .environment(RewardsViewModel())
        .environment(IncomingFileRouter())
}
