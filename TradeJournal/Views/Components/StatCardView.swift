import SwiftUI

/// Herbruikbare KPI-kaart voor het dashboard: titel, waarde en optioneel
/// een subtitel (bijv. aantal trades achter een ratio).
struct StatCardView: View {

    let title: String
    let value: String
    var subtitle: String? = nil
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        StatCardView(title: "Netto P&L", value: "$1.240", valueColor: Theme.profit)
        StatCardView(title: "Win rate", value: "58%", subtitle: "24 trades")
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
