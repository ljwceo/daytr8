import SwiftUI
import Charts

/// Horizontale staafdiagram van netto P&L per groep (confluence, playbook,
/// sessie, ...). Toont maximaal `maxBars` groepen (de resultaten worden al
/// gesorteerd aangeleverd) zodat de as leesbaar blijft.
struct GroupedBarChartView: View {

    let results: [GroupResult]
    var maxBars: Int = 8

    private var bars: [GroupResult] { Array(results.prefix(maxBars)) }

    var body: some View {
        if bars.isEmpty {
            Text("Nog geen data")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            Chart(bars) { result in
                BarMark(
                    x: .value("Netto P&L", result.statistics.netPnL),
                    y: .value("Groep", result.label)
                )
                .foregroundStyle(Theme.color(forPnL: result.statistics.netPnL))
                RuleMark(x: .value("Nul", 0))
                    .foregroundStyle(Theme.separator)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: CGFloat(bars.count) * 32 + 24)
        }
    }
}
