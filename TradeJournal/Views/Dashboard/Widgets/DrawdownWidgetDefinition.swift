import SwiftUI

/// Drawdown onder de nullijn (hergebruikt `EquityCurveChartView`).
struct DrawdownWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.drawdown
    let title = "Drawdown"
    let systemImage = "chart.line.downtrend.xyaxis"
    let summary = "Afstand tot de vorige piek van je equity."
    let defaultSize = WidgetSize.large
    let options: WidgetSettingsOptions = [.period, .accounts]

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        let points = context.cached("drawdown") { context.dashboardModel.drawdownPoints(for: context.filteredTrades) }
        return AnyView(
            EquityCurveChartView(points: points, lineColor: Theme.loss)
                .frame(height: context.size == .large ? Theme.widgetChartHeightLarge : Theme.widgetChartHeightSmall)
        )
    }
}
