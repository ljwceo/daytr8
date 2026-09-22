import SwiftUI

/// Placeholder voor de Trades-tab (trade log).
/// Wordt in een latere fase een doorzoekbare lijst met tradedetail en snel-toevoegen.
struct TradesView: View {

    var body: some View {
        PlaceholderView(
            title: "Trades",
            systemImage: "list.bullet.rectangle",
            subtitle: "Doorzoekbare trade log met filters, swipe-acties en tradedetail."
        )
    }
}

#Preview {
    TradesView()
        .preferredColorScheme(.dark)
}
