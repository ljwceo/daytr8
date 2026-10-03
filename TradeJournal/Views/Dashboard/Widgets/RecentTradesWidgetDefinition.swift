import SwiftUI

/// Meest recente trades (hergebruikt `TradeRowView`).
struct RecentTradesWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.recentTrades
    let title = "Recente trades"
    let systemImage = "list.bullet.rectangle"
    let summary = "De laatste trades uit de selectie; tik voor details."
    let defaultSize = WidgetSize.large
    let options: WidgetSettingsOptions = [.period, .accounts, .itemCount]
    var defaultSettings: WidgetSettings { WidgetSettings(itemCount: 5) }

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        let trades = context.cached("recent") {
            context.dashboardModel.recentTrades(from: context.filteredTrades, limit: max(context.settings.itemCount, 1))
        }
        guard !trades.isEmpty else {
            return AnyView(WidgetEmptyStateView(text: "Nog geen trades in deze selectie."))
        }
        let stats = context.dataService.statsService
        return AnyView(
            VStack(spacing: 0) {
                ForEach(Array(trades.enumerated()), id: \.element.id) { index, trade in
                    NavigationLink(value: trade) {
                        TradeRowView(trade: trade, metrics: stats.metrics(for: trade))
                    }
                    .buttonStyle(.plain)
                    if index < trades.count - 1 {
                        Divider().background(Theme.separator)
                    }
                }
            }
        )
    }
}
