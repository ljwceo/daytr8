import SwiftUI
import SwiftData

/// Voorlopige "Meer"-tab.
///
/// In fase 1 dient dit scherm vooral als ingang voor de debug-tools:
/// - Standaard-data seeden (confluences + instrumentpresets)
/// - ~2 jaar aan voorbeelddata genereren
/// - Alle data wissen
///
/// In een latere fase wordt dit uitgebouwd tot een volwaardig instellingenmenu
/// met accounts, playbooks, backup, thema-opties etc.
struct MoreView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var accounts: [Account]
    @Query private var trades: [Trade]
    @Query private var confluences: [Confluence]
    @Query private var instruments: [Instrument]

    @State private var isBusy = false
    @State private var confirmWipe = false
    @State private var lastMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                List {
                    Section("Overzicht") {
                        row("Accounts", value: "\(accounts.count)")
                        row("Trades", value: "\(trades.count)")
                        row("Confluences", value: "\(confluences.count)")
                        row("Instrumenten", value: "\(instruments.count)")
                    }

                    Section("Debug (fase 1)") {
                        Button {
                            perform { SeedService.seedDefaultsIfNeeded(in: modelContext) }
                            lastMessage = "Standaardconfluences en instrumentpresets ingeschoten."
                        } label: {
                            Label("Standaarddata inschieten", systemImage: "square.and.arrow.down")
                        }
                        .disabled(isBusy)

                        Button {
                            perform {
                                let count = SampleDataService.generate(in: modelContext)
                                lastMessage = "\(count) voorbeeldtrades toegevoegd."
                            }
                        } label: {
                            Label("Voorbeelddata genereren (~2 jaar)", systemImage: "wand.and.stars")
                        }
                        .disabled(isBusy)

                        Button(role: .destructive) {
                            confirmWipe = true
                        } label: {
                            Label("Alles wissen", systemImage: "trash")
                        }
                        .disabled(isBusy)
                    }

                    if let lastMessage {
                        Section {
                            Text(lastMessage)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
            }
            .navigationTitle("Meer")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog(
                "Weet je zeker dat je alle data wilt wissen?",
                isPresented: $confirmWipe,
                titleVisibility: .visible
            ) {
                Button("Wissen", role: .destructive) {
                    perform {
                        SampleDataService.wipeAll(in: modelContext)
                        lastMessage = "Alle data is gewist."
                    }
                }
                Button("Annuleren", role: .cancel) { }
            } message: {
                Text("Deze actie kan niet ongedaan gemaakt worden.")
            }
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
    }

    private func perform(_ work: @escaping () -> Void) {
        isBusy = true
        DispatchQueue.main.async {
            work()
            isBusy = false
        }
    }
}

#Preview {
    MoreView()
        .modelContainer(for: AppSchema.models, inMemory: true)
        .preferredColorScheme(.dark)
}
