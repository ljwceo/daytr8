import SwiftUI

/// Horizontale rij met filter-chips voor het dashboard: periode, account(s),
/// symbool, playbook en confluence. Elke chip opent een `Menu` met de opties.
struct DashboardFilterBar: View {

    @Bindable var viewModel: DashboardViewModel
    let accounts: [Account]
    let symbols: [String]
    let playbooks: [Playbook]
    let confluences: [Confluence]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                periodMenu
                if !accounts.isEmpty { accountMenu }
                if !symbols.isEmpty { symbolMenu }
                if !playbooks.isEmpty { playbookMenu }
                if !confluences.isEmpty { confluenceMenu }
                backtestToggle
            }
            .padding(.vertical, 2)
        }
    }

    private var periodMenu: some View {
        Menu {
            Picker("Periode", selection: $viewModel.period) {
                ForEach(DashboardViewModel.Period.allCases) { period in
                    Text(period.displayName).tag(period)
                }
            }
        } label: {
            filterChip(title: viewModel.period.displayName, isActive: viewModel.period != .all, icon: "calendar")
        }
    }

    private var accountMenu: some View {
        Menu {
            ForEach(accounts) { account in
                Button {
                    viewModel.toggleAccount(account)
                } label: {
                    if viewModel.selectedAccountIDs.contains(account.id) {
                        Label(account.name, systemImage: "checkmark")
                    } else {
                        Text(account.name)
                    }
                }
            }
            if !viewModel.selectedAccountIDs.isEmpty {
                Divider()
                Button("Alle accounts tonen") { viewModel.selectedAccountIDs.removeAll() }
            }
        } label: {
            filterChip(
                title: viewModel.selectedAccountIDs.isEmpty ? "Alle accounts" : "\(viewModel.selectedAccountIDs.count) account(s)",
                isActive: !viewModel.selectedAccountIDs.isEmpty,
                icon: "person.crop.circle"
            )
        }
    }

    private var symbolMenu: some View {
        Menu {
            Button("Alle symbolen") { viewModel.symbolFilter = nil }
            ForEach(symbols, id: \.self) { symbol in
                Button(symbol) { viewModel.symbolFilter = symbol }
            }
        } label: {
            filterChip(title: viewModel.symbolFilter ?? "Symbool", isActive: viewModel.symbolFilter != nil, icon: "chart.xyaxis.line")
        }
    }

    private var playbookMenu: some View {
        Menu {
            Button("Alle playbooks") { viewModel.playbookID = nil }
            ForEach(playbooks) { playbook in
                Button(playbook.name) { viewModel.playbookID = playbook.id }
            }
        } label: {
            filterChip(
                title: playbooks.first { $0.id == viewModel.playbookID }?.name ?? "Playbook",
                isActive: viewModel.playbookID != nil,
                icon: "book"
            )
        }
    }

    private var confluenceMenu: some View {
        Menu {
            Button("Alle confluences") { viewModel.confluenceID = nil }
            ForEach(confluences) { confluence in
                Button(confluence.name) { viewModel.confluenceID = confluence.id }
            }
        } label: {
            filterChip(
                title: confluences.first { $0.id == viewModel.confluenceID }?.name ?? "Confluence",
                isActive: viewModel.confluenceID != nil,
                icon: "square.grid.2x2"
            )
        }
    }

    /// Backtest-trades meetellen of niet (standaard uit).
    private var backtestToggle: some View {
        Button {
            viewModel.includeBacktest.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.includeBacktest ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                    .font(.caption)
                Text("Backtest").font(.subheadline.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(viewModel.includeBacktest ? Theme.onAccent : Theme.textPrimary)
            .background(viewModel.includeBacktest ? Theme.accent.opacity(0.85) : Theme.elevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func filterChip(title: String, isActive: Bool, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(isActive ? Theme.onAccent : Theme.textPrimary)
        .background(isActive ? Theme.accent.opacity(0.85) : Theme.elevated)
        .clipShape(Capsule())
    }
}
