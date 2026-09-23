import SwiftUI

/// Doelen per account op het dashboard (SPEC §10): voortgangsbalk voor het
/// maandelijkse P&L-doel en balken voor daily loss limit en max drawdown,
/// met een waarschuwing zodra een limiet dichtbij is.
struct GoalsCardView: View {

    let statuses: [AccountGoalStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Doelen & limieten")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            ForEach(statuses) { status in
                VStack(alignment: .leading, spacing: 10) {
                    Text(status.accountName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    if let target = status.monthlyTarget {
                        bar(
                            title: "Maanddoel",
                            value: "\(money(target.current, status.currency)) / \(money(target.target, status.currency))",
                            fraction: target.fraction,
                            color: target.isReached ? Theme.profit : Theme.accent
                        )
                    }
                    if let daily = status.dailyLoss {
                        bar(
                            title: "Daily loss limit",
                            value: "\(money(daily.used, status.currency)) van \(money(daily.limit, status.currency))",
                            fraction: daily.fraction,
                            color: color(for: daily.level)
                        )
                    }
                    if let drawdown = status.drawdown {
                        bar(
                            title: "Max drawdown",
                            value: "\(money(drawdown.used, status.currency)) van \(money(drawdown.limit, status.currency))",
                            fraction: drawdown.fraction,
                            color: color(for: drawdown.level)
                        )
                    }
                }
                if status.id != statuses.last?.id {
                    Divider().background(Theme.separator)
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func bar(title: String, value: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(value).font(.caption.monospacedDigit()).foregroundStyle(Theme.textPrimary)
            }
            ProgressView(value: fraction)
                .tint(color)
        }
    }

    private func color(for level: GoalLevel) -> Color {
        switch level {
        case .ok: return Theme.profit
        case .warning: return Theme.warning
        case .breached: return Theme.loss
        }
    }

    private func money(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}
