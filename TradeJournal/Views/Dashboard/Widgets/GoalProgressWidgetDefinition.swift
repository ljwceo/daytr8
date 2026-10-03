import SwiftUI

/// Doelvoortgang per account: maanddoel, daily loss limit en max drawdown
/// (hergebruikt `GoalsListView` en `GoalsService`).
struct GoalProgressWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.goalProgress
    let title = "Doelen & limieten"
    let systemImage = "target"
    let summary = "Maanddoel en prop firm-limieten (daily loss, max drawdown) per account."
    let defaultSize = WidgetSize.large
    let options: WidgetSettingsOptions = [.accounts]

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        let selected = Set(context.filter.selectedAccountIDs)
        let accounts = selected.isEmpty ? context.accounts : context.accounts.filter { selected.contains($0.id) }
        let statuses = context.cached("goals") {
            context.dashboardModel.goalStatuses(accounts: accounts, trades: context.allTrades)
        }
        if statuses.isEmpty {
            return AnyView(WidgetEmptyStateView(text: "Geen doelen ingesteld. Stel een maanddoel of limieten in via Meer → Accounts & doelen."))
        }
        return AnyView(GoalsListView(statuses: statuses))
    }
}
