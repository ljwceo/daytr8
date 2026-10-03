import SwiftUI
import Charts

/// Histogram van R-multiples (bakken van 1R, label = ondergrens; de
/// buitenste bakken vangen de uitschieters). Alleen trades met een bekend risico tellen mee.
struct RHistogramWidgetView: View {

    let context: WidgetRenderContext

    var body: some View {
        let buckets = context.cached("rhistogram") { context.dataService.rHistogram(for: context.filteredTrades, bucketWidth: 1) }
        if buckets.isEmpty {
            WidgetEmptyStateView(
                text: "Geen R-multiples: vul een stop loss of gepland risico in bij je trades.",
                minHeight: context.size == .large ? Theme.widgetChartHeightLarge : Theme.widgetChartHeightSmall
            )
        } else {
            let lossColor = Theme.loss
            let profitColor = Theme.profit
            Chart(buckets) { bucket in
                BarMark(x: .value("R", bucket.label), y: .value("Trades", bucket.count))
                    .foregroundStyle(bucket.isLoss ? lossColor : profitColor)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: context.size == .large ? Theme.widgetChartHeightLarge : Theme.widgetChartHeightSmall)
        }
    }
}

/// Verdeling van de behaalde R-multiples.
struct RHistogramWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.rHistogram
    let title = "R-multiple histogram"
    let systemImage = "chart.bar"
    let summary = "Hoe je resultaten verdeeld zijn in R: hoeveel trades eindigen rond -1R, 0R, +2R, …"
    let defaultSize = WidgetSize.large
    let options: WidgetSettingsOptions = [.period, .accounts]

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        AnyView(RHistogramWidgetView(context: context))
    }
}
