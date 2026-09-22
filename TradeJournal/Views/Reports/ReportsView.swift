import SwiftUI

/// Placeholder voor de Rapporten-tab.
/// Wordt in een latere fase gevuld met analyses per confluence, playbook, sessie, etc.
struct ReportsView: View {

    var body: some View {
        PlaceholderView(
            title: "Rapporten",
            systemImage: "chart.bar.doc.horizontal",
            subtitle: "Analyses per confluence, playbook, symbool, sessie en meer."
        )
    }
}

#Preview {
    ReportsView()
        .preferredColorScheme(.dark)
}
