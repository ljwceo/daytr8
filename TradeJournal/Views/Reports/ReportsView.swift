import SwiftUI
import SwiftData

/// Rapporten-tab (`SPEC.md §7`): breakdown-tabbladen per confluence,
/// confluentiecombinatie, playbook, symbool, richting, sessie, dag van de
/// week, uur van de dag, trade-duur, tag, mistake, emotie en rating — elk
/// met een staafdiagram + tabel, filterbaar en met een vergelijkingsmodus
/// (twee filtersets naast elkaar).
struct ReportsView: View {

    @Query(sort: \Trade.entryDate, order: .reverse) private var trades: [Trade]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Playbook.name) private var playbooks: [Playbook]
    @Query(sort: \Confluence.sortOrder) private var confluences: [Confluence]

    @State private var viewModel = ReportsViewModel()

    private var currencyCode: String { accounts.first?.currency ?? "USD" }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if trades.isEmpty {
                    PlaceholderView(
                        title: "Rapporten",
                        systemImage: "chart.bar.doc.horizontal",
                        subtitle: "Analyses per confluence, playbook, symbool, sessie en meer verschijnen hier zodra je trades hebt gelogd."
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Rapporten")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { viewModel.compareMode.toggle() }
                    } label: {
                        Label("Vergelijken", systemImage: viewModel.compareMode ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    }
                }
            }
        }
    }

    // MARK: - Layout

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterSection
                tabPicker
                if viewModel.compareMode {
                    compareContent
                } else {
                    singleContent
                }
            }
            .padding(16)
        }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardFilterBar(
                viewModel: viewModel.primaryFilter,
                accounts: accounts,
                symbols: viewModel.primaryFilter.availableSymbols(from: trades),
                playbooks: playbooks,
                confluences: confluences
            )

            if viewModel.compareMode {
                Text("Vergelijk met")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                DashboardFilterBar(
                    viewModel: viewModel.secondaryFilter,
                    accounts: accounts,
                    symbols: viewModel.secondaryFilter.availableSymbols(from: trades),
                    playbooks: playbooks,
                    confluences: confluences
                )
            }
        }
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReportsViewModel.Tab.allCases) { tab in
                    Button {
                        viewModel.selectedTab = tab
                    } label: {
                        Text(tab.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(viewModel.selectedTab == tab ? Theme.onAccent : Theme.textPrimary)
                            .background(viewModel.selectedTab == tab ? Theme.accent.opacity(0.85) : Theme.elevated)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Enkele filterset

    private var singleContent: some View {
        let filtered = viewModel.primaryTrades(trades)
        let results = viewModel.groupResults(for: viewModel.selectedTab, trades: filtered)

        return VStack(alignment: .leading, spacing: 16) {
            card(title: "Netto P&L per \(viewModel.selectedTab.displayName.lowercased())") {
                GroupedBarChartView(results: results)
            }

            card(title: viewModel.selectedTab.displayName, trailing: { sortMenu }) {
                resultsList(results)
            }
        }
    }

    // MARK: - Vergelijkingsmodus

    private var compareContent: some View {
        let primaryTrades = viewModel.primaryTrades(trades)
        let secondaryTrades = viewModel.secondaryTrades(trades)
        let primaryResults = viewModel.groupResults(for: viewModel.selectedTab, trades: primaryTrades)
        let secondaryResults = viewModel.groupResults(for: viewModel.selectedTab, trades: secondaryTrades)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                compareSummaryCard(title: "A", trades: primaryTrades)
                compareSummaryCard(title: "B", trades: secondaryTrades)
            }

            card(title: viewModel.selectedTab.displayName, trailing: { sortMenu }) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("A").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        resultsList(primaryResults)
                    }
                    Divider().background(Theme.separator)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("B").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        resultsList(secondaryResults)
                    }
                }
            }
        }
    }

    private func compareSummaryCard(title: String, trades: [Trade]) -> some View {
        let stats = viewModel.primaryFilter.statistics(for: trades)
        return card(title: title) {
            VStack(alignment: .leading, spacing: 6) {
                Text(stats.netPnL.formatted(.currency(code: currencyCode).precision(.fractionLength(0))))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.color(forPnL: stats.netPnL))
                Text("\(percent(stats.winRate)) win rate · \(stats.tradeCount) trades")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                Text("Expectancy \(stats.expectancy.formatted(.currency(code: currencyCode).precision(.fractionLength(0))))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Herbruikbare stukjes

    private func resultsList(_ results: [GroupResult]) -> some View {
        Group {
            if results.isEmpty {
                Text("Geen data voor dit filter.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(results) { result in
                        GroupResultRowView(result: result, currencyCode: currencyCode)
                        if result.id != results.last?.id {
                            Divider().background(Theme.separator)
                        }
                    }
                }
            }
        }
    }

    private var sortMenu: some View {
        Group {
            if viewModel.selectedTab.isUserSortable {
                Menu {
                    Picker("Sorteer op", selection: $viewModel.sortKey) {
                        ForEach(ReportsViewModel.SortKey.allCases) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    Button {
                        viewModel.sortAscending.toggle()
                    } label: {
                        Label(viewModel.sortAscending ? "Oplopend" : "Aflopend", systemImage: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        card(title: title, trailing: { EmptyView() }, content: content)
    }

    private func card<Trailing: View, Content: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

#Preview {
    ReportsView()
        .modelContainer(for: AppSchema.models, inMemory: true)
        .preferredColorScheme(.dark)
}
