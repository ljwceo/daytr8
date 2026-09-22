import SwiftUI

/// Eén dagvakje in de maandkalender: dagnummer, netto P&L en aantal trades.
/// De achtergrondintensiteit schaalt met de grootte van de P&L t.o.v. de
/// grootste dag in de zichtbare maand (`maxAbsPnL`).
struct CalendarDayCellView: View {

    let date: Date
    let aggregate: DayAggregate?
    let maxAbsPnL: Double
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.day()))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            if let aggregate, aggregate.tradeCount > 0 {
                Text(Theme.compactCurrency(aggregate.netPnL))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.color(forPnL: aggregate.netPnL))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("\(aggregate.tradeCount) trade\(aggregate.tradeCount == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Spacer(minLength: 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(4)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
        )
    }

    private var intensity: Double {
        guard let aggregate, maxAbsPnL > 0 else { return 0 }
        return min(abs(aggregate.netPnL) / maxAbsPnL, 1)
    }

    private var backgroundColor: Color {
        guard let aggregate, aggregate.tradeCount > 0 else { return Theme.card }
        return Theme.color(forPnL: aggregate.netPnL).opacity(0.18 + intensity * 0.55)
    }

    private var borderColor: Color {
        if isSelected { return Theme.accent }
        if isToday { return Theme.accent.opacity(0.5) }
        return .clear
    }
}

#Preview {
    HStack {
        CalendarDayCellView(
            date: Date(),
            aggregate: DayAggregate(date: Date(), netPnL: 1240, grossPnL: 1260, tradeCount: 3, winCount: 2, lossCount: 1, breakevenCount: 0, openCount: 0, winRate: 0.66),
            maxAbsPnL: 1240,
            isToday: true,
            isSelected: false
        )
        CalendarDayCellView(date: Date(), aggregate: nil, maxAbsPnL: 1240, isToday: false, isSelected: false)
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
