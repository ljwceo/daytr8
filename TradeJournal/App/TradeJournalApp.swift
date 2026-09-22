import SwiftUI
import SwiftData

@main
struct TradeJournalApp: App {

    @Environment(\.scenePhase) private var scenePhase

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
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    // Idempotente seed van standaardconfluences en instrumentpresets
                    // bij de eerste app-start. Loopt op de main-actor (task in body).
                    SeedService.seedDefaultsIfNeeded(in: container.mainContext)
                    // Automatische backup naar de gekozen map (als ingesteld).
                    AutoBackupService().runIfDue(context: container.mainContext, isLaunch: true)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Bij terugkeer naar de voorgrond: dagelijkse backup inhalen.
                    guard phase == .active else { return }
                    AutoBackupService().runIfDue(context: container.mainContext, isLaunch: false)
                }
        }
        .modelContainer(container)
    }
}
