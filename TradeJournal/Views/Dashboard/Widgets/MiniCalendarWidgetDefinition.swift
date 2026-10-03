import SwiftUI

/// Mini-kalender van de huidige maand (hergebruikt `MiniCalendarView`).
struct MiniCalendarWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.miniCalendar
    let title = "Deze maand"
    let systemImage = "calendar"
    let summary = "Kalender van de huidige maand met P&L-kleur per dag."
    let defaultSize = WidgetSize.large
    let options: WidgetSettingsOptions = [.accounts]

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        // De maand staat vast; de periode van het dashboard telt hier niet.
        let filter = context.dataService.effectiveFilter(base: context.baseFilter, settings: context.settings, includePeriod: false)
        let aggregates = context.cached("month") {
            context.dataService.aggregationService.dayAggregates(for: context.dataService.trades(context.allTrades, matching: filter))
        }
        return AnyView(MiniCalendarView(dayAggregates: aggregates))
    }
}
