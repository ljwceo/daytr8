import SwiftUI

/// Statistiekkaart: één kengetal naar keuze plus de verandering t.o.v. de
/// vorige periode (vorige week/maand/jaar, of een even lange periode vóór
/// een aangepaste periode).
struct StatisticWidgetView: View {

    let context: WidgetRenderContext

    private var metric: WidgetSettings.Metric { context.settings.metric }

    var body: some View {
        let stats = context.cached("stats") { context.dataService.statsService.statistics(for: context.filteredTrades) }
        let comparison = context.cached("comparison") {
            context.dataService.comparison(of: metric, trades: context.allTrades, state: context.filter)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(valueText(stats))
                .font(context.size == .large ? .title2.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(valueColor(stats))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let subtitle = subtitle(stats) {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            changeView(comparison)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Waarde

    private func valueText(_ stats: TradeStatistics) -> String {
        let currency = context.currency
        switch metric {
        case .netPnL: return stats.netPnL.formatted(.currency(code: currency))
        case .winRate: return WidgetFormat.percent(stats.winRate)
        case .profitFactor:
            guard let factor = stats.profitFactor else { return "—" }
            return factor.isInfinite ? "∞" : String(format: "%.2f", factor)
        case .expectancy: return stats.expectancy.formatted(.currency(code: currency))
        case .averageR: return stats.averageRMultiple.map { String(format: "%.2fR", $0) } ?? "—"
        case .maxDrawdown: return WidgetFormat.money(stats.maxDrawdown, currency)
        case .tradeCount: return "\(stats.tradeCount)"
        case .streak: return stats.currentStreak == 0 ? "—" : "\(stats.currentStreak)"
        case .averageWinLoss:
            return "\(WidgetFormat.money(stats.averageWin, currency)) / \(WidgetFormat.money(stats.averageLoss, currency))"
        case .largestWinLoss:
            return "\(WidgetFormat.money(stats.largestWin, currency)) / \(WidgetFormat.money(stats.largestLoss, currency))"
        }
    }

    private func subtitle(_ stats: TradeStatistics) -> String? {
        switch metric {
        case .netPnL: return "\(stats.tradeCount) trades"
        case .winRate: return "\(stats.winCount)W / \(stats.lossCount)L"
        case .maxDrawdown: return WidgetFormat.percent(stats.maxDrawdownPercent)
        case .streak:
            guard let winning = stats.currentStreakIsWinning else { return nil }
            return winning ? "op rij winst" : "op rij verlies"
        default: return nil
        }
    }

    private func valueColor(_ stats: TradeStatistics) -> Color {
        switch metric {
        case .netPnL: return Theme.color(forPnL: stats.netPnL)
        case .expectancy: return Theme.color(forPnL: stats.expectancy)
        case .maxDrawdown: return Theme.loss
        case .streak:
            guard let winning = stats.currentStreakIsWinning else { return Theme.textPrimary }
            return winning ? Theme.profit : Theme.loss
        default: return Theme.textPrimary
        }
    }

    // MARK: - Verandering

    @ViewBuilder
    private func changeView(_ comparison: MetricComparison) -> some View {
        if let change = comparison.change {
            let improved = metric.lowerIsBetter ? change < 0 : change > 0
            let color = change == 0 ? Theme.neutral : (improved ? Theme.profit : Theme.loss)
            HStack(spacing: 4) {
                Image(systemName: change > 0 ? "arrow.up.right" : (change < 0 ? "arrow.down.right" : "equal"))
                    .font(.caption2.weight(.bold))
                Text(changeText(change))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                Text("vs vorige")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else if context.filter.period == DashboardViewModel.Period.all.rawValue, metric != .streak, comparison.current != nil {
            Text("Geen vergelijking bij 'Alles'")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }

    private func changeText(_ change: Double) -> String {
        let sign = change > 0 ? "+" : ""
        switch metric {
        case .netPnL, .expectancy, .maxDrawdown:
            return sign + change.formatted(.currency(code: context.currency).precision(.fractionLength(0)))
        case .winRate:
            return sign + String(format: "%.0f", change * 100) + " pp"
        case .profitFactor:
            return sign + String(format: "%.2f", change)
        case .averageR:
            return sign + String(format: "%.2fR", change)
        case .tradeCount:
            return sign + String(format: "%.0f", change)
        case .streak, .averageWinLoss, .largestWinLoss:
            return ""
        }
    }
}

/// Statistiekkaart met één kengetal naar keuze.
struct StatisticWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.statistic
    let title = "Statistiekkaart"
    let systemImage = "number.square"
    let summary = "Eén kengetal (P&L, win rate, profit factor, …) met verandering t.o.v. de vorige periode."
    let defaultSize = WidgetSize.small
    let options: WidgetSettingsOptions = [.period, .accounts, .metric]

    func defaultTitle(for settings: WidgetSettings) -> String {
        settings.metric.displayName
    }

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        AnyView(StatisticWidgetView(context: context))
    }
}
