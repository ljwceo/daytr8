import SwiftUI

/// Tabbladen met de dashboards van de gebruiker ("Overzicht", "Prop firm",
/// …). Tik = openen; lang indrukken = hernoemen, verplaatsen of
/// verwijderen. In de bewerkmodus staat er een "+" om een dashboard toe te
/// voegen.
struct DashboardTabsBar: View {

    let dashboards: [Dashboard]
    let selectedID: UUID?
    let isEditing: Bool
    let onSelect: (Dashboard) -> Void
    let onAdd: () -> Void
    let onRename: (Dashboard) -> Void
    let onMove: (Dashboard, Int) -> Void
    let onDelete: (Dashboard) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(dashboards.enumerated()), id: \.element.id) { index, dashboard in
                    ChipView(
                        title: dashboard.name,
                        color: Theme.accent,
                        selectedForeground: Theme.onAccent,
                        isSelected: dashboard.id == (selectedID ?? dashboards.first?.id)
                    ) {
                        onSelect(dashboard)
                    }
                    .contextMenu {
                        Button { onRename(dashboard) } label: { Label("Hernoemen", systemImage: "pencil") }
                        if index > 0 {
                            Button { onMove(dashboard, -1) } label: { Label("Naar links", systemImage: "arrow.left") }
                        }
                        if index < dashboards.count - 1 {
                            Button { onMove(dashboard, 1) } label: { Label("Naar rechts", systemImage: "arrow.right") }
                        }
                        if dashboards.count > 1 {
                            Button(role: .destructive) { onDelete(dashboard) } label: { Label("Verwijderen", systemImage: "trash") }
                        }
                    }
                }
                if isEditing {
                    ChipView(title: "Nieuw", systemImage: "plus", color: Theme.accent, isSelected: false) {
                        onAdd()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
