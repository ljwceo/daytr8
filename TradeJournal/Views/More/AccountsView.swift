import SwiftUI
import SwiftData

/// Accountbeheer: accounts aanmaken/bewerken/verwijderen, inclusief doelen en
/// limieten en het accounttype (backtest-accounts tellen niet mee in de live
/// statistieken).
struct AccountsView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Account.createdAt) private var accounts: [Account]

    @State private var showingNew = false
    @State private var editing: Account?
    @State private var pendingDelete: Account?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                if accounts.isEmpty {
                    Text("Nog geen accounts. Voeg er een toe om doelen en limieten in te stellen.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.card)
                }
                ForEach(accounts) { account in
                    Button {
                        editing = account
                    } label: {
                        row(account)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDelete = account
                        } label: {
                            Label("Verwijderen", systemImage: "trash")
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Text("Trades van backtest-accounts tellen standaard niet mee op het dashboard, in rapporten, de kalender en de progress tracker. Zet \"Backtest\" aan in de filters om ze te analyseren.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Accounts & doelen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNew = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            AccountFormView(mode: .create)
        }
        .sheet(item: $editing) { account in
            AccountFormView(mode: .edit(account))
        }
        .confirmationDialog(
            "Account verwijderen?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Verwijderen", role: .destructive) {
                if let account = pendingDelete {
                    AccountFormViewModel.delete(account, in: modelContext)
                }
                pendingDelete = nil
            }
            Button("Annuleren", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Alle trades van dit account worden ook verwijderd. Dit kan niet ongedaan gemaakt worden.")
        }
    }

    private func row(_ account: Account) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(account.isArchived ? Theme.textTertiary : Theme.textPrimary)
                    Text(account.type.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                        .foregroundStyle(account.type == .backtest ? Theme.warning : Theme.textSecondary)
                }
                Text(goalSummary(account))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func goalSummary(_ account: Account) -> String {
        var parts: [String] = [account.startingBalance.formatted(.currency(code: account.currency).precision(.fractionLength(0)))]
        if let target = account.monthlyProfitTarget {
            parts.append("doel \(Theme.compactCurrency(target))/mnd")
        }
        if let daily = account.dailyLossLimit {
            parts.append("DLL \(Theme.compactCurrency(daily))")
        }
        if let drawdown = account.maxDrawdown {
            parts.append("max DD \(Theme.compactCurrency(drawdown))")
        }
        if account.isArchived { parts.append("gearchiveerd") }
        return parts.joined(separator: " · ")
    }
}
