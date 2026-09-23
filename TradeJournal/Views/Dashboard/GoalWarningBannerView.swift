import SwiftUI

/// Waarschuwing bovenaan het dashboard als een account dicht bij (of over)
/// zijn daily loss limit of max drawdown zit.
struct GoalWarningBannerView: View {

    let statuses: [AccountGoalStatus]

    private var warnings: [String] {
        statuses.flatMap { status -> [String] in
            var lines: [String] = []
            if let daily = status.dailyLoss, daily.level != .ok {
                lines.append(daily.level == .breached
                    ? "\(status.accountName): daily loss limit bereikt — stop met handelen vandaag."
                    : "\(status.accountName): nog \(money(daily.remaining, status.currency)) tot je daily loss limit.")
            }
            if let drawdown = status.drawdown, drawdown.level != .ok {
                lines.append(drawdown.level == .breached
                    ? "\(status.accountName): max drawdown bereikt."
                    : "\(status.accountName): nog \(money(drawdown.remaining, status.currency)) tot je max drawdown.")
            }
            return lines
        }
    }

    var body: some View {
        if !warnings.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { line in
                        Text(line)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.warning.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.warning.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private func money(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}
