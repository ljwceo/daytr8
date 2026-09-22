import SwiftUI

/// Compacte, alleen-lezen kalender van één maand voor op het dashboard.
struct MiniCalendarView: View {

    let dayAggregates: [Date: DayAggregate]
    var referenceDate: Date = Date()
    var calendar: Calendar = .current

    private var weeks: [[Date?]] {
        CalendarViewModel.weeks(forMonth: referenceDate, calendar: calendar)
    }

    private var maxAbsPnL: Double {
        weeks.flatMap { $0 }.compactMap { $0 }
            .compactMap { dayAggregates[calendar.startOfDay(for: $0)] }
            .map { abs($0.netPnL) }
            .max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(referenceDate.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let aggregate = dayAggregates[calendar.startOfDay(for: day)]
            let intensity: Double = {
                guard let aggregate, maxAbsPnL > 0 else { return 0 }
                return min(abs(aggregate.netPnL) / maxAbsPnL, 1)
            }()
            let background: Color = {
                guard let aggregate, aggregate.tradeCount > 0 else { return Theme.elevated }
                return Theme.color(forPnL: aggregate.netPnL).opacity(0.25 + intensity * 0.6)
            }()

            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 26)
        }
    }
}
