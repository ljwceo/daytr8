import SwiftUI

/// Consistentie-kalender van de progress tracker: kolommen per week, rijen
/// per weekdag. Een cel is groen bij een perfecte dag, oranje bij een
/// gedeeltelijk gevolgde dag, rood als geen enkele regel gevolgd is en leeg
/// als er die dag niets te beoordelen viel.
struct ConsistencyHeatmapView: View {

    let weeks: [[Date?]]
    let progress: [Date: DayProgress]
    var onSelect: ((Date) -> Void)? = nil

    private let cellSpacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let columns = CGFloat(max(weeks.count, 1))
                let byWidth = (proxy.size.width - cellSpacing * (columns - 1)) / columns
                let byHeight = (proxy.size.height - cellSpacing * 6) / 7
                let size = max(min(byWidth, byHeight), 4)
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: cellSpacing) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                cell(for: day)
                                    .frame(width: size, height: size)
                            }
                        }
                    }
                }
            }
            // Verhouding kolommen : 7 rijen, zodat de cellen vierkant blijven.
            .aspectRatio(CGFloat(max(weeks.count, 1)) / 7, contentMode: .fit)

            legend
        }
    }

    @ViewBuilder
    private func cell(for day: Date?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        if let day {
            shape
                .fill(color(for: progress[day]))
                .onTapGesture { onSelect?(day) }
        } else {
            shape.fill(Color.clear)
        }
    }

    private func color(for day: DayProgress?) -> Color {
        guard let day, day.isTracked, let score = day.score else { return Theme.elevated }
        if day.isPerfect { return Theme.profit }
        if score == 0 { return Theme.loss.opacity(0.8) }
        return Theme.warning.opacity(0.4 + 0.5 * score)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(Theme.profit, "Alle regels")
            legendItem(Theme.warning.opacity(0.7), "Deels")
            legendItem(Theme.loss.opacity(0.8), "Geen")
            legendItem(Theme.elevated, "Niet gevolgd")
        }
        .font(.caption2)
        .foregroundStyle(Theme.textSecondary)
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }
}
