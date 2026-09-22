import SwiftUI

/// Placeholder voor de Kalender-tab.
/// Wordt in een latere fase een maandweergave met P&L per dag en een jaarheatmap.
struct CalendarView: View {

    var body: some View {
        PlaceholderView(
            title: "Kalender",
            systemImage: "calendar",
            subtitle: "Maandweergave met P&L per dag, wekelijkse totalen en jaaroverzicht."
        )
    }
}

#Preview {
    CalendarView()
        .preferredColorScheme(.dark)
}
