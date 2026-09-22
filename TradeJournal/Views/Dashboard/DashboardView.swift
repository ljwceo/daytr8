import SwiftUI

/// Placeholder voor het Dashboard-scherm.
/// Wordt in een latere fase gevuld met KPI-kaarten, equity curve en trading score.
struct DashboardView: View {

    var body: some View {
        PlaceholderView(
            title: "Dashboard",
            systemImage: "chart.line.uptrend.xyaxis",
            subtitle: "Netto P&L, win rate, profit factor en trading score verschijnen hier."
        )
    }
}

#Preview {
    DashboardView()
        .preferredColorScheme(.dark)
}
