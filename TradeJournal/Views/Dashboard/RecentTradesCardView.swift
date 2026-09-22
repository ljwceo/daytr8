import SwiftUI

/// Kaart met de meest recente trades uit de huidige dashboard-selectie.
struct RecentTradesCardView: View {

    let trades: [Trade]
    let statsService: StatsService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recente trades")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            if trades.isEmpty {
                Text("Nog geen trades in deze selectie.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(trades.enumerated()), id: \.element.id) { index, trade in
                        NavigationLink(value: trade) {
                            TradeRowView(trade: trade, metrics: statsService.metrics(for: trade))
                        }
                        .buttonStyle(.plain)
                        if index < trades.count - 1 {
                            Divider().background(Theme.separator)
                        }
                    }
                }
            }
        }
        .padding(Theme.cardPadding)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
