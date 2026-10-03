import SwiftUI

/// Top/flop-lijst: beste en slechtste symbolen, confluences, playbooks of
/// sessies op netto P&L (groepering via `ReportAggregationService`).
struct TopFlopWidgetView: View {

    let context: WidgetRenderContext

    var body: some View {
        let lists = context.cached("topflop") {
            context.dataService.topFlop(for: context.filteredTrades, dimension: context.settings.dimension, count: context.settings.itemCount)
        }
        if lists.top.isEmpty && lists.flop.isEmpty {
            WidgetEmptyStateView(text: "Nog geen gesloten trades in deze selectie.")
        } else if context.size == .large {
            HStack(alignment: .top, spacing: Theme.widgetSpacing) {
                column(title: "Top", systemImage: "arrow.up.right", groups: lists.top)
                column(title: "Flop", systemImage: "arrow.down.right", groups: lists.flop)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                column(title: "Top", systemImage: "arrow.up.right", groups: lists.top)
                column(title: "Flop", systemImage: "arrow.down.right", groups: lists.flop)
            }
        }
    }

    private func column(title: String, systemImage: String, groups: [GroupResult]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            if groups.isEmpty {
                Text("—").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            ForEach(groups) { group in
                HStack(spacing: 6) {
                    Text(group.label)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Theme.compactCurrency(group.statistics.netPnL))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.color(forPnL: group.statistics.netPnL))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Beste en slechtste groepen naar keuze.
struct TopFlopWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.topFlop
    let title = "Top & flop"
    let systemImage = "arrow.up.arrow.down"
    let summary = "Beste en slechtste symbolen, confluences, playbooks of sessies op netto P&L."
    let defaultSize = WidgetSize.large
    let options: WidgetSettingsOptions = [.period, .accounts, .dimension, .itemCount]

    func defaultTitle(for settings: WidgetSettings) -> String {
        "Top & flop: \(settings.dimension.displayName.lowercased())"
    }

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        AnyView(TopFlopWidgetView(context: context))
    }
}
