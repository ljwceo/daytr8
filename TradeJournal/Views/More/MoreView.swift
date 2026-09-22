import SwiftUI

/// Placeholder voor de Meer-tab.
/// Wordt in een latere fase de ingang naar instellingen, backups, accounts, playbooks etc.
struct MoreView: View {

    var body: some View {
        PlaceholderView(
            title: "Meer",
            systemImage: "ellipsis.circle",
            subtitle: "Accounts, playbooks, confluences, backup en instellingen."
        )
    }
}

#Preview {
    MoreView()
        .preferredColorScheme(.dark)
}
