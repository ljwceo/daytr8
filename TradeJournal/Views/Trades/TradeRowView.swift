import Foundation
import SwiftUI

/// Eén rij in het trade log: richting, symbool, datum/sessie en netto P&L /
/// R-multiple in één oogopslag.
struct TradeRowView: View {

    let trade: Trade
    let metrics: TradeMetrics

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trade.direction == .long ? "arrow.up.right" : "arrow.down.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(rowColor)
                .frame(width: 28, height: 28)
                .background(rowColor.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(trade.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    Text(trade.entryDate.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(trade.session.displayName)
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if metrics.outcome == .open {
                    Text("Open")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.neutral)
                } else {
                    Text(metrics.netPnL.formatted(.currency(code: trade.account?.currency ?? "USD")))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(rowColor)
                    if let r = metrics.rMultiple {
                        Text(String(format: "%.2fR", r))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var rowColor: Color {
        metrics.outcome == .open ? Theme.neutral : Theme.color(forPnL: metrics.netPnL)
    }
}
