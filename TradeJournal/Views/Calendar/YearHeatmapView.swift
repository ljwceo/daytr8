import SwiftUI

/// Jaaroverzicht: 12 mini-maanden met dag-kleurtjes (heatmap-stijl) en het
/// totale P&L per maand. Tikken op een maand springt naar de maandweergave.
struct YearHeatmapView: View {

    let viewModel: CalendarViewModel
    let dayAggregates: [Date: DayAggregate]
    let monthAggregates: [Date: MonthAggregate]
    let onSelectMonth: (Int) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var yearTotal: Double {
        (1...12).reduce(0) { $0 + (monthAggregate(month: $1)?.netPnL ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Jaartotaal")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(yearTotal.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                    .font(.headline)
                    .foregroundStyle(Theme.color(forPnL: yearTotal))
            }
            .padding(Theme.cardPadding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...12, id: \.self) { month in
                    miniMonth(month)
                }
            }
        }
    }

    /// `monthAggregates` is sleutelbaar op `calendar.date(from: [.year, .month])`
    /// (zie `CalendarAggregationService.monthAggregates`) — dezelfde opbouw hier
    /// garandeert dat de lookup matcht.
    private func monthAggregate(month: Int) -> MonthAggregate? {
        var comps = DateComponents()
        comps.year = viewModel.displayedYear
        comps.month = month
        guard let date = viewModel.calendar.date(from: comps) else { return nil }
        return monthAggregates[date]
    }

    private func miniMonth(_ month: Int) -> some View {
        var comps = DateComponents()
        comps.year = viewModel.displayedYear
        comps.month = month
        comps.day = 1
        let monthDate = viewModel.calendar.date(from: comps) ?? Date()
        let aggregate = monthAggregate(month: month)

        return Button {
            onSelectMonth(month)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(monthDate.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                MiniMonthGridView(month: monthDate, calendar: viewModel.calendar, dayAggregates: dayAggregates)

                Text(aggregate.map { Theme.compactCurrency($0.netPnL) } ?? "—")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(aggregate.map { Theme.color(forPnL: $0.netPnL) } ?? Theme.textTertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Compacte dag-heatmap (kleine gekleurde vierkantjes, geen tekst) voor één maand.
private struct MiniMonthGridView: View {
    let month: Date
    let calendar: Calendar
    let dayAggregates: [Date: DayAggregate]

    private var weeks: [[Date?]] {
        CalendarViewModel.weeks(forMonth: month, calendar: calendar)
    }

    private var maxAbsPnL: Double {
        weeks.flatMap { $0 }.compactMap { $0 }
            .compactMap { dayAggregates[calendar.startOfDay(for: $0)] }
            .map { abs($0.netPnL) }
            .max() ?? 0
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 2) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color(for: day))
                            .frame(height: 6)
                    }
                }
            }
        }
    }

    private func color(for day: Date?) -> Color {
        guard let day, let aggregate = dayAggregates[calendar.startOfDay(for: day)], aggregate.tradeCount > 0 else {
            return Theme.separator
        }
        let intensity = maxAbsPnL > 0 ? min(abs(aggregate.netPnL) / maxAbsPnL, 1) : 0
        return Theme.color(forPnL: aggregate.netPnL).opacity(0.35 + intensity * 0.65)
    }
}
