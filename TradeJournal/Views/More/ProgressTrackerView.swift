import SwiftUI
import SwiftData

/// Progress tracker (SPEC §10): dagelijkse regels afvinken, huidige en
/// langste streak, consistentie en een consistentie-kalender van de laatste
/// weken. Tik op een dag in de kalender om die dag te bekijken of af te vinken.
struct ProgressTrackerView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DailyRule.sortOrder) private var rules: [DailyRule]
    @Query private var checks: [DailyRuleCheck]
    @Query(sort: \Trade.entryDate) private var trades: [Trade]
    @Query(sort: \DailyJournal.date) private var journals: [DailyJournal]

    @State private var viewModel = ProgressTrackerViewModel()

    var body: some View {
        let allProgress = viewModel.allProgress(rules: rules, trades: trades, journals: journals, checks: checks)
        let summary = viewModel.summary(for: allProgress)
        let selected = viewModel.dayProgress(for: viewModel.selectedDate, rules: rules, trades: trades, journals: journals, checks: checks)

        return ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryGrid(summary)

                    card(title: "Consistentie — laatste \(ProgressTrackerViewModel.heatmapWeeks) weken") {
                        ConsistencyHeatmapView(
                            weeks: viewModel.heatmapWeeks(),
                            progress: allProgress,
                            onSelect: { viewModel.selectedDate = $0 }
                        )
                    }

                    card(title: checklistTitle) {
                        DatePicker("Dag", selection: $viewModel.selectedDate, in: ...Date(), displayedComponents: .date)
                            .foregroundStyle(Theme.textSecondary)
                        RuleChecklistView(progress: selected) { ruleID in
                            guard let rule = rules.first(where: { $0.id == ruleID }) else { return }
                            viewModel.toggleCheck(for: rule, on: viewModel.selectedDate, in: modelContext)
                        }
                        if let score = selected.score {
                            Text("\(selected.followedCount) van \(selected.ruleCount) regels gevolgd (\(score.formatted(.percent.precision(.fractionLength(0)))))")
                                .font(.caption)
                                .foregroundStyle(selected.isPerfect ? Theme.profit : Theme.textSecondary)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Progress tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    DailyRulesView()
                } label: {
                    Text("Regels")
                }
            }
        }
    }

    private var checklistTitle: String {
        Calendar.current.isDateInToday(viewModel.selectedDate)
            ? "Vandaag"
            : viewModel.selectedDate.formatted(date: .complete, time: .omitted)
    }

    private func summaryGrid(_ summary: ProgressSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCardView(
                title: "Huidige streak",
                value: "\(summary.currentStreak)",
                subtitle: summary.currentStreak == 1 ? "dag alle regels" : "dagen alle regels",
                valueColor: summary.currentStreak > 0 ? Theme.profit : Theme.textPrimary
            )
            StatCardView(title: "Langste streak", value: "\(summary.longestStreak)", subtitle: "dagen")
            StatCardView(
                title: "Consistentie",
                value: summary.consistency.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                subtitle: "\(summary.perfectDays) van \(summary.trackedDays) dagen"
            )
            StatCardView(title: "Actieve regels", value: "\(rules.filter(\.isActive).count)")
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            content()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
