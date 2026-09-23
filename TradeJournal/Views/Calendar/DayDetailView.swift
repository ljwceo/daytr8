import SwiftUI
import SwiftData

/// Dagdetail (tik op een dag in de kalender): alle trades van die dag,
/// intraday cumulatieve P&L, het daily journal en snel een trade toevoegen.
struct DayDetailView: View {

    let date: Date

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Trade.entryDate, order: .reverse) private var allTrades: [Trade]
    @Query(sort: \DailyJournal.date) private var allJournals: [DailyJournal]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \JournalTemplate.sortOrder) private var templates: [JournalTemplate]
    @Query(sort: \DailyRule.sortOrder) private var rules: [DailyRule]
    @Query private var ruleChecks: [DailyRuleCheck]
    @Query(sort: \NotebookNote.updatedAt, order: .reverse) private var notes: [NotebookNote]

    @State private var viewModel: DayDetailViewModel
    @State private var progressViewModel = ProgressTrackerViewModel()
    @State private var notebookViewModel = NotebookViewModel()
    @State private var showingNewTrade = false
    @State private var noteTarget: NoteEditorTarget?

    private let calendar = Calendar.current
    private let statsService = StatsService()

    init(date: Date) {
        self.date = date
        _viewModel = State(initialValue: DayDetailViewModel(date: date, journal: nil))
    }

    @AppStorage(CalendarViewModel.includeBacktestKey) private var includeBacktest = false

    private var dayTrades: [Trade] {
        viewModel.trades(from: CalendarViewModel.visibleTrades(allTrades, includeBacktest: includeBacktest), calendar: calendar)
    }

    private var existingJournal: DailyJournal? {
        allJournals.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard

                    if dayTrades.count > 1 {
                        card(title: "Intraday P&L") {
                            EquityCurveChartView(points: viewModel.intradayEquityPoints(for: dayTrades))
                                .frame(height: 160)
                        }
                    }

                    tradesCard
                    journalCard
                    rulesCard
                    notesCard
                }
                .padding(16)
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewTrade = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(for: Trade.self) { trade in
            TradeDetailView(trade: trade)
        }
        .sheet(item: $noteTarget) { target in
            NoteEditorView(note: target.note, linkedDate: target.linkedDate, linkedTrade: target.linkedTrade)
        }
        .sheet(isPresented: $showingNewTrade) {
            TradeFormView(mode: .create, lastTrade: allTrades.first, fallbackAccount: accounts.first, initialDate: date)
        }
        .onAppear {
            viewModel.resetDraft(from: existingJournal)
        }
    }

    // MARK: - Secties

    private var summaryCard: some View {
        let stats = viewModel.statistics(for: dayTrades)
        let currency = dayTrades.first?.account?.currency ?? "USD"

        return card(title: "Samenvatting") {
            HStack {
                metricColumn(title: "Netto P&L", value: stats.netPnL.formatted(.currency(code: currency)), color: Theme.color(forPnL: stats.netPnL))
                metricColumn(title: "Trades", value: "\(stats.tradeCount)", color: Theme.textPrimary)
                metricColumn(title: "Win rate", value: stats.winRate.formatted(.percent.precision(.fractionLength(0))), color: Theme.textPrimary)
            }
        }
    }

    private var tradesCard: some View {
        card(title: "Trades") {
            if dayTrades.isEmpty {
                Text("Nog geen trades op deze dag.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dayTrades.enumerated()), id: \.element.id) { index, trade in
                        NavigationLink(value: trade) {
                            TradeRowView(trade: trade, metrics: statsService.metrics(for: trade))
                        }
                        .buttonStyle(.plain)
                        if index < dayTrades.count - 1 {
                            Divider().background(Theme.separator)
                        }
                    }
                }
            }
        }
    }

    private var journalCard: some View {
        card(title: "Dagjournal") {
            VStack(alignment: .leading, spacing: 12) {
                templateMenu
                labeledField("Pre-market plan", text: $viewModel.journalDraft.preMarketPlan)
                labeledField("Dagelijkse bias", text: $viewModel.journalDraft.dailyBias)
                labeledField("Nieuws & events", text: $viewModel.journalDraft.newsAndEvents)
                labeledField("Post-market review", text: $viewModel.journalDraft.postMarketReview)
                labeledField("Mood", text: $viewModel.journalDraft.mood)

                Stepper("Cijfer voor de dag: \(viewModel.journalDraft.dayRating == 0 ? "—" : "\(viewModel.journalDraft.dayRating)/10")", value: $viewModel.journalDraft.dayRating, in: 0...10)
                    .foregroundStyle(Theme.textPrimary)

                Button {
                    viewModel.saveJournal(existing: existingJournal, in: modelContext)
                } label: {
                    Text("Journal opslaan")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 10)
                .background(Theme.accent)
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
            }
        }
    }

    /// Menu om een pre-/post-market-template in het concept te zetten.
    @ViewBuilder
    private var templateMenu: some View {
        if !templates.isEmpty {
            Menu {
                ForEach(JournalTemplateKind.allCases) { kind in
                    Section(kind.displayName) {
                        ForEach(viewModel.templateService.sorted(templates.filter { $0.kind == kind })) { template in
                            Button(template.name.isEmpty ? kind.displayName : template.name) {
                                viewModel.applyTemplate(template)
                            }
                        }
                    }
                }
            } label: {
                Label("Template invoegen", systemImage: "doc.text")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    private var rulesCard: some View {
        let progress = progressViewModel.dayProgress(
            for: date,
            rules: rules,
            trades: CalendarViewModel.visibleTrades(allTrades, includeBacktest: false),
            journals: allJournals,
            checks: ruleChecks
        )
        return card(title: "Dagelijkse regels") {
            RuleChecklistView(progress: progress) { ruleID in
                guard let rule = rules.first(where: { $0.id == ruleID }) else { return }
                progressViewModel.toggleCheck(for: rule, on: date, in: modelContext)
            }
        }
    }

    private var notesCard: some View {
        let dayNotes = notebookViewModel.notes(linkedTo: date, from: notes)
        return card(title: "Notities") {
            ForEach(dayNotes) { note in
                Button {
                    noteTarget = NoteEditorTarget(note: note)
                } label: {
                    NoteRowView(note: note)
                }
                .buttonStyle(.plain)
            }
            Button {
                noteTarget = NoteEditorTarget(note: nil, linkedDate: date)
            } label: {
                Label("Notitie toevoegen", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    // MARK: - Helpers

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            TextField(title, text: text, axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(Theme.textPrimary)
                .padding(8)
                .background(Theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
        }
    }

    private func metricColumn(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
