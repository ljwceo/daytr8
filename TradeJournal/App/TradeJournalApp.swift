import SwiftUI
import SwiftData

@main
struct TradeJournalApp: App {

    @Environment(\.scenePhase) private var scenePhase

    /// App-slot (Face ID / code), gedeeld met het instellingenscherm via de environment.
    @State private var appLock = AppLockViewModel()

    /// Welkomstmelding, rondleiding en tabselectie.
    @State private var onboarding = OnboardingViewModel()

    /// Eén centrale `ModelContainer` voor de hele app — bevat het volledige
    /// schema uit `AppSchema.models`.
    let container: ModelContainer = {
        do {
            return try ModelContainer(for: Schema(AppSchema.models))
        } catch {
            fatalError("Kon SwiftData ModelContainer niet initialiseren: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .overlay {
                    if appLock.isLocked {
                        AppLockOverlayView(viewModel: appLock)
                    }
                }
                .environment(appLock)
                .environment(onboarding)
                // Color scheme volgt het gekozen thema en staat op `RootTabView`.
                .tint(Theme.accent)
                .task {
                    // Idempotente seed van standaardconfluences en instrumentpresets
                    // bij de eerste app-start. Loopt op de main-actor (task in body).
                    SeedService.seedDefaultsIfNeeded(in: container.mainContext)
                    // Automatische backup naar de gekozen map (als ingesteld).
                    AutoBackupService().runIfDue(context: container.mainContext, isLaunch: true)
                    // Eerste start: welkomstmelding (verschijnt na ontgrendelen).
                    onboarding.handleLaunch()
                    // Koude start: direct om ontgrendeling vragen als het slot aan staat.
                    await appLock.unlock()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        appLock.didEnterBackground()
                    case .active:
                        Task { await appLock.didBecomeActive() }
                        // Bij terugkeer naar de voorgrond: dagelijkse backup inhalen.
                        AutoBackupService().runIfDue(context: container.mainContext, isLaunch: false)
                    default:
                        break
                    }
                }
        }
        .modelContainer(container)
    }
}
