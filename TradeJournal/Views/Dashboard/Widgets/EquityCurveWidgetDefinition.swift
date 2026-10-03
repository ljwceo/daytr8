import SwiftUI

/// Cumulatieve equity curve (hergebruikt `EquityCurveChartView`).
struct EquityCurveWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.equityCurve
    let title = "Equity curve"
    let systemImage = "chart.line.uptrend.xyaxis"
    let summary = "Cumulatieve netto P&L over de gekozen periode."
    let defaultSize = WidgetSize.large
    let options: WidgetSettingsOptions = [.period, .accounts]

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        let points = context.cached("equity") { context.dashboardModel.equityPoints(for: context.filteredTrades) }
        return AnyView(
            EquityCurveChartView(points: points)
                .frame(height: context.size == .large ? Theme.widgetChartHeightLarge : Theme.widgetChartHeightSmall)
        )
    }
}
