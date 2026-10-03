import SwiftUI

/// Regels/consistentie-streak uit de progress tracker: huidige en langste
/// streak, consistentie en de laatste 14 dagen als stippen.
struct RuleStreakWidgetView: View {

    let context: WidgetRenderContext

    private let service = ProgressTrackerService()
    private let calendar = Calendar.current
    private static let recentDayCount = 14

    var body: some View {
        let progress = context.cached("progress") {
            service.progress(rules: context.rules, trades: context.allTrades, journals: context.journals, checks: context.ruleChecks, calendar: calendar)
        }
        let summary = service.summary(for: progress, calendar: calendar)

        if context.rules.filter(\.isActive).isEmpty {
            WidgetEmptyStateView(text: "Nog geen dagelijkse regels. Voeg ze toe in Meer → Progress tracker.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(summary.currentStreak > 0 ? Theme.warning : Theme.textTertiary)
                    Text("\(summary.currentStreak)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text(summary.currentStreak == 1 ? "dag op rij" : "dagen op rij")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 12) {
                    detail("Langste", "\(summary.longestStreak)")
                    detail("Consistentie", summary.consistency.map { WidgetFormat.percent($0) } ?? "—")
                }
                recentDays(progress)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Theme.textTertiary)
            Text(value).font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
    }

    private func recentDays(_ progress: [Date: DayProgress]) -> some View {
        let today = calendar.startOfDay(for: Date())
        let days: [Date] = (0..<Self.recentDayCount).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        return HStack(spacing: 3) {
            ForEach(days, id: \.self) { day in
                Circle()
                    .fill(color(for: progress[day]))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityLabel("Laatste \(Self.recentDayCount) dagen")
    }

    private func color(for day: DayProgress?) -> Color {
        guard let day, day.isTracked, day.ruleCount > 0 else { return Theme.heatmapEmpty }
        if day.isPerfect { return Theme.profit }
        return day.followedCount > 0 ? Theme.warning : Theme.loss
    }
}

/// Streak van dagen waarop alle regels gevolgd zijn.
struct RuleStreakWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.ruleStreak
    let title = "Regels & consistentie"
    let systemImage = "flame"
    let summary = "Streak van dagen waarop je al je dagelijkse regels volgde, met consistentie."
    let defaultSize = WidgetSize.small
    let options: WidgetSettingsOptions = []

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        AnyView(RuleStreakWidgetView(context: context))
    }
}
