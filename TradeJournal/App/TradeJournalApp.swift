import SwiftUI

@main
struct TradeJournalApp: App {

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
