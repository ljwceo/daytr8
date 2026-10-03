import SwiftUI

/// Dagelijkse P&L als staven (hergebruikt `DailyPnLChartView`).
struct DailyPnLWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.dailyPnL
    let title = "Dagelijkse P&L"
    let systemImage = "chart.bar.xaxis"
    let summary = "Netto P&L per handelsdag, groen/rood per staaf."
    let defaultSize = WidgetSize.large
    let options: WidgetSettingsOptions = [.period, .accounts]

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        let points = context.cached("daily") { context.dashboardModel.dailyPnLPoints(for: context.filteredTrades) }
        return AnyView(
            DailyPnLChartView(points: points)
                .frame(height: context.size == .large ? Theme.widgetChartHeightLarge : Theme.widgetChartHeightSmall)
        )
    }
}
