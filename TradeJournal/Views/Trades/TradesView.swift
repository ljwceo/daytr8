import SwiftUI
import SwiftData

/// Trade log: doorzoekbare, sorteerbare lijst van alle trades met
/// snelfilters, swipe-acties (dupliceren/verwijderen) en een link naar
/// `TradeDetailView`. Nieuwe trades worden aangemaakt via `TradeFormView`.
struct TradesView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingViewModel.self) private var onboarding

    @Query(sort: \Trade.entryDate, order: .reverse) private var trades: [Trade]
    @Query(sort: \Account.createdAt) private var accounts: [Account]

    @State private var viewModel = TradesListViewModel()
    @State private var showingNewTrade = false
    @State private var tradeToDelete: Trade?

    private var visibleTrades: [Trade] {
        viewModel.filteredAndSorted(trades)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if trades.isEmpty {
                    PlaceholderView(
                        title: "Nog geen trades",
                        systemImage: "list.bullet.rectangle",
                        subtitle: "Tik op + om je eerste trade te loggen."
                    )
                } else {
                    List {
                        quickFilterRow

                        ForEach(visibleTrades) { trade in
                            NavigationLink(value: trade) {
                                TradeRowView(trade: trade, metrics: viewModel.metrics(for: trade))
                            }
                            .listRowBackground(Theme.card)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    tradeToDelete = trade
                                } label: {
                                    Label("Verwijderen", systemImage: "trash")
                                }
                                Button {
                                    viewModel.duplicate(trade, in: modelContext)
                                } label: {
                                    Label("Dupliceren", systemImage: "doc.on.doc")
                                }
                                .tint(Theme.accent)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                    .searchable(text: $viewModel.searchText, prompt: "Zoek op symbool, playbook, tag...")
                }
            }
            .navigationTitle("Trades")
            .navigationDestination(for: Trade.self) { trade in
                TradeDetailView(trade: trade)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sorteren", selection: $viewModel.sortOption) {
                            ForEach(TradesListViewModel.SortOption.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        Picker("Richting", selection: $viewModel.directionFilter) {
                            Text("Alle richtingen").tag(Optional<TradeDirection>.none)
                            ForEach(TradeDirection.allCases) { direction in
                                Text(direction.displayName).tag(Optional(direction))
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewTrade = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // "Eerste trade toevoegen" aan het einde van de rondleiding.
            .onAppear { openRequestedNewTrade() }
            .onChange(of: onboarding.isNewTradeRequested) { _, _ in openRequestedNewTrade() }
            .sheet(isPresented: $showingNewTrade) {
                TradeFormView(mode: .create, lastTrade: trades.first, fallbackAccount: accounts.first)
            }
            .confirmationDialog(
                "Trade verwijderen?",
                isPresented: Binding(get: { tradeToDelete != nil }, set: { if !$0 { tradeToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Verwijderen", role: .destructive) {
                    if let trade = tradeToDelete {
                        viewModel.delete(trade, from: modelContext)
                    }
                    tradeToDelete = nil
                }
                Button("Annuleren", role: .cancel) { tradeToDelete = nil }
            }
        }
    }

    private func openRequestedNewTrade() {
        if onboarding.consumeNewTradeRequest() {
            showingNewTrade = true
        }
    }

    private var quickFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TradesListViewModel.QuickFilter.allCases) { filter in
                    ChipView(
                        title: filter.displayName,
                        color: Theme.accent,
                        selectedForeground: Theme.onAccent,
                        isSelected: viewModel.quickFilter == filter
                    ) {
                        viewModel.quickFilter = filter
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Theme.background)
    }
}

#Preview {
    TradesView()
        .environment(OnboardingViewModel())
        .modelContainer(for: AppSchema.models, inMemory: true)
        .preferredColorScheme(.dark)
}
