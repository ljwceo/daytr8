import SwiftUI
import Charts

/// Staafdiagram van netto P&L per dag, groen/rood per staaf.
struct DailyPnLChartView: View {

    let points: [DateValuePoint]

    var body: some View {
        if points.isEmpty {
            Text("Nog geen data")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Chart(points) { point in
                BarMark(x: .value("Datum", point.date), y: .value("Netto P&L", point.value))
                    .foregroundStyle(Theme.color(forPnL: point.value))
                RuleMark(y: .value("Nul", 0))
                    .foregroundStyle(Theme.separator)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}
