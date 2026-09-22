import SwiftUI

/// Maandraster met weekdag-header, dagvakjes en een weektotalen-kolom.
struct CalendarMonthGridView: View {

    let viewModel: CalendarViewModel
    let dayAggregates: [Date: DayAggregate]
    let onSelectDay: (Date) -> Void

    private var maxAbsPnL: Double {
        dayAggregates.values.map { abs($0.netPnL) }.max() ?? 0
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(viewModel.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                Text("TOT")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 52)
            }

            ForEach(Array(viewModel.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            Button {
                                onSelectDay(day)
                            } label: {
                                CalendarDayCellView(
                                    date: day,
                                    aggregate: dayAggregates[viewModel.calendar.startOfDay(for: day)],
                                    maxAbsPnL: maxAbsPnL,
                                    isToday: viewModel.calendar.isDateInToday(day),
                                    isSelected: viewModel.selectedDate.map {
                                        viewModel.calendar.isDate($0, inSameDayAs: day)
                                    } ?? false
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 56)
                        }
                    }
                    weekTotalCell(for: week)
                }
            }
        }
    }

    private func weekTotalCell(for week: [Date?]) -> some View {
        let hasData = week.compactMap { $0 }.contains { dayAggregates[viewModel.calendar.startOfDay(for: $0)] != nil }
        let total = viewModel.weekTotal(for: week, dayAggregates: dayAggregates)

        return Text(hasData ? Theme.compactCurrency(total) : "—")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(hasData ? Theme.color(forPnL: total) : Theme.textTertiary)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: 52)
            .frame(minHeight: 56)
            .padding(4)
            .background(Theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
