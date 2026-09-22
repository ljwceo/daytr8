import SwiftUI

/// Hoofdnavigatie met de vijf top-level tabs.
/// Alle tabs zijn in fase 0 nog placeholders; ze worden per fase uitgebouwd.
struct RootTabView: View {

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }

            CalendarView()
                .tabItem {
                    Label("Kalender", systemImage: "calendar")
                }

            TradesView()
                .tabItem {
                    Label("Trades", systemImage: "list.bullet.rectangle")
                }

            ReportsView()
                .tabItem {
                    Label("Rapporten", systemImage: "chart.bar.doc.horizontal")
                }

            MoreView()
                .tabItem {
                    Label("Meer", systemImage: "ellipsis.circle")
                }
        }
        .background(Theme.background)
    }
}

#Preview {
    RootTabView()
        .preferredColorScheme(.dark)
}
