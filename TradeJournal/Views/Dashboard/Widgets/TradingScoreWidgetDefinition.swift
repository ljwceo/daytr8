import SwiftUI

/// Trading score als radar (hergebruikt `TradingScoreRadarView`).
struct TradingScoreWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.tradingScore
    let title = "Trading score"
    let systemImage = "hexagon"
    let summary = "Samengestelde score op win rate, profit factor, consistentie en meer."
    let defaultSize = WidgetSize.large
    let supportedSizes: [WidgetSize] = [.large]
    let options: WidgetSettingsOptions = [.period, .accounts]

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        let score = context.cached("score") { context.dashboardModel.tradingScore(for: context.filteredTrades) }
        return AnyView(TradingScoreRadarView(score: score))
    }
}
