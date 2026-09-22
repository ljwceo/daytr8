import SwiftUI

/// Eén rij in een rapportage-tabel: groep-label, aantal trades, win rate,
/// netto P&L en gemiddelde R. Wordt zowel los als naast een tweede kolom
/// (vergelijkingsmodus) gebruikt.
struct GroupResultRowView: View {

    let result: GroupResult
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            if let colorHex = result.colorHex {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(result.statistics.tradeCount) trades · \(percent(result.statistics.winRate)) win rate")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(result.statistics.netPnL.formatted(.currency(code: currencyCode).precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.color(forPnL: result.statistics.netPnL))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let avgR = result.statistics.averageRMultiple {
                    Text(String(format: "%.2fR", avgR))
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

#Preview {
    GroupResultRowView(
        result: GroupResult(id: "1", label: "Sweep PDL", statistics: .empty, colorHex: "#F5A64C"),
        currencyCode: "USD"
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
