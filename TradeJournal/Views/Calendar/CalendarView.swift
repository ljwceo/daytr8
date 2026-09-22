import SwiftUI
import SwiftData

/// Kalender-tab: maandweergave met P&L/trades/win rate per dag, weektotalen,
/// een jaaroverzicht (heatmap) en navigatie naar `DayDetailView`.
struct CalendarView: View {

    @Query(sort: \Trade.entryDate) private var trades: [Trade]

    @State private var viewModel = CalendarViewModel()

    private let aggregationService = CalendarAggregationService()

    private var dayAggregates: [Date: DayAggregate] {
        aggregationService.dayAggregates(for: trades, calendar: viewModel.calendar)
    }

    private var monthAggregates: [Date: MonthAggregate] {
        aggregationService.monthAggregates(fromDayAggregates: dayAggregates, calendar: viewModel.calendar)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if trades.isEmpty {
                    PlaceholderView(
                        title: "Kalender",
                        systemImage: "calendar",
                        subtitle: "Zodra je trades logt, zie je hier je P&L per dag terug."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            navigationHeader

                            if viewModel.showYearOverview {
                                YearHeatmapView(
                                    viewModel: viewModel,
                                    dayAggregates: dayAggregates,
                                    monthAggregates: monthAggregates,
                                    onSelectMonth: { month in
                                        viewModel.selectMonth(month, in: viewModel.displayedYear)
                                    }
                                )
                            } else {
                                CalendarMonthGridView(
                                    viewModel: viewModel,
                                    dayAggregates: dayAggregates,
                                    onSelectDay: { day in
                                        viewModel.selectedDate = viewModel.calendar.startOfDay(for: day)
                                    }
                                )
                                .padding(Theme.cardPadding)
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                                .gesture(
                                    DragGesture(minimumDistance: 30)
                                        .onEnded { value in
                                            if value.translation.width < 0 {
                                                viewModel.nextMonth()
                                            } else if value.translation.width > 0 {
                                                viewModel.previousMonth()
                                            }
                                        }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Kalender")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Vandaag") {
                        viewModel.goToToday()
                    }
                }
            }
            .navigationDestination(item: $viewModel.selectedDate) { date in
                DayDetailView(date: date)
            }
        }
    }

    private var navigationHeader: some View {
        HStack {
            Button {
                if viewModel.showYearOverview {
                    viewModel.previousYear()
                } else {
                    viewModel.previousMonth()
                }
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Button {
                viewModel.showYearOverview.toggle()
            } label: {
                VStack(spacing: 2) {
                    Text(viewModel.showYearOverview ? String(viewModel.displayedYear) : viewModel.monthTitle)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(viewModel.showYearOverview ? "Terug naar maand" : "Jaaroverzicht")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer()

            Button {
                if viewModel.showYearOverview {
                    viewModel.nextYear()
                } else {
                    viewModel.nextMonth()
                }
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 4)
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: AppSchema.models, inMemory: true)
        .preferredColorScheme(.dark)
}
