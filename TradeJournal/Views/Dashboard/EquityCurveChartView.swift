import SwiftUI
import Charts

/// Lijn + vulling-grafiek voor een cumulatieve reeks (equity curve, intraday
/// P&L). Herbruikt door het dashboard én de dagdetail (intraday-grafiek).
struct EquityCurveChartView: View {

    let points: [DateValuePoint]
    var lineColor: Color = Theme.accent

    var body: some View {
        if points.isEmpty {
            emptyState
        } else {
            Chart(points) { point in
                LineMark(x: .value("Datum", point.date), y: .value("Waarde", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(lineColor)
                AreaMark(x: .value("Datum", point.date), y: .value("Waarde", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(colors: [lineColor.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    )
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

    private var emptyState: some View {
        Text("Nog geen data")
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}
