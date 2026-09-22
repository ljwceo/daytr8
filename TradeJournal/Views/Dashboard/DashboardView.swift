import SwiftUI
import SwiftData

/// Dashboard-tab: filters, KPI-kaarten, trading score radar, equity curve,
/// dagelijkse P&L, drawdown, mini-kalender en recente trades.
struct DashboardView: View {

    @Query(sort: \Trade.entryDate, order: .reverse) private var trades: [Trade]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Playbook.name) private var playbooks: [Playbook]
    @Query(sort: \Confluence.sortOrder) private var confluences: [Confluence]

    @State private var viewModel = DashboardViewModel()

    private let statsService = StatsService()

    private var filteredTrades: [Trade] {
        viewModel.filteredTrades(trades)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if trades.isEmpty {
                    PlaceholderView(
                        title: "Dashboard",
                        systemImage: "chart.line.uptrend.xyaxis",
                        subtitle: "Netto P&L, win rate, profit factor en trading score verschijnen hier zodra je trades hebt gelogd."
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            DashboardFilterBar(
                                viewModel: viewModel,
                                accounts: accounts,
                                symbols: viewModel.availableSymbols(from: trades),
                                playbooks: playbooks,
                                confluences: confluences
                            )

                            statCardsGrid

                            scoreCard

                            card(title: "Equity curve") {
                                EquityCurveChartView(points: viewModel.equityPoints(for: filteredTrades))
                                    .frame(height: 180)
                            }

                            card(title: "Dagelijkse P&L") {
                                DailyPnLChartView(points: viewModel.dailyPnLPoints(for: filteredTrades))
                                    .frame(height: 160)
                            }

                            card(title: "Drawdown") {
                                EquityCurveChartView(points: viewModel.drawdownPoints(for: filteredTrades), lineColor: Theme.loss)
                                    .frame(height: 140)
                            }

                            miniCalendarCard

                            RecentTradesCardView(
                                trades: viewModel.recentTrades(from: filteredTrades),
                                statsService: statsService
                            )
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Dashboard")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: Trade.self) { trade in
                TradeDetailView(trade: trade)
            }
        }
    }

    // MARK: - Secties

    private var statCardsGrid: some View {
        let stats = viewModel.statistics(for: filteredTrades)
        let currency = accounts.first?.currency ?? "USD"
        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 12) {
            StatCardView(
                title: "Netto P&L",
                value: stats.netPnL.formatted(.currency(code: currency)),
                subtitle: "\(stats.tradeCount) trades",
                valueColor: Theme.color(forPnL: stats.netPnL)
            )
            StatCardView(title: "Win rate", value: percent(stats.winRate), subtitle: "\(stats.winCount)W / \(stats.lossCount)L")
            StatCardView(title: "Profit factor", value: profitFactorText(stats.profitFactor))
            StatCardView(title: "Expectancy", value: stats.expectancy.formatted(.currency(code: currency)), valueColor: Theme.color(forPnL: stats.expectancy))
            StatCardView(
                title: "Gem. winst / verlies",
                value: "\(stats.averageWin.formatted(.currency(code: currency).precision(.fractionLength(0)))) / \(stats.averageLoss.formatted(.currency(code: currency).precision(.fractionLength(0))))"
            )
            StatCardView(title: "Gem. R", value: stats.averageRMultiple.map { String(format: "%.2fR", $0) } ?? "—")
            StatCardView(
                title: "Grootste winst / verlies",
                value: "\(stats.largestWin.formatted(.currency(code: currency).precision(.fractionLength(0)))) / \(stats.largestLoss.formatted(.currency(code: currency).precision(.fractionLength(0))))"
            )
            StatCardView(
                title: "Max drawdown",
                value: stats.maxDrawdown.formatted(.currency(code: currency).precision(.fractionLength(0))),
                subtitle: percent(stats.maxDrawdownPercent),
                valueColor: Theme.loss
            )
            StatCardView(
                title: "Streak",
                value: stats.currentStreak == 0 ? "—" : "\(stats.currentStreak)",
                subtitle: streakSubtitle(stats),
                valueColor: streakColor(stats)
            )
        }
    }

    private var scoreCard: some View {
        card(title: "Trading score") {
            TradingScoreRadarView(score: viewModel.tradingScore(for: filteredTrades))
        }
    }

    private var miniCalendarCard: some View {
        card(title: "Deze maand") {
            MiniCalendarView(dayAggregates: viewModel.aggregationService.dayAggregates(for: filteredTrades))
        }
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

    // MARK: - Helpers

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func profitFactorText(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value.isInfinite { return "∞" }
        return String(format: "%.2f", value)
    }

    private func streakSubtitle(_ stats: TradeStatistics) -> String {
        guard let isWinning = stats.currentStreakIsWinning else { return "—" }
        return isWinning ? "op rij winst" : "op rij verlies"
    }

    private func streakColor(_ stats: TradeStatistics) -> Color {
        guard let isWinning = stats.currentStreakIsWinning else { return Theme.textPrimary }
        return isWinning ? Theme.profit : Theme.loss
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: AppSchema.models, inMemory: true)
        .preferredColorScheme(.dark)
}
