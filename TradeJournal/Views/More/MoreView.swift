import SwiftUI
import SwiftData

/// "Meer"-tab.
///
/// - Data: backup & herstel (incl. automatische backup en CSV-export) en
///   CSV-import (fase 5).
/// - Debug-tools uit fase 1: standaarddata seeden, ~2 jaar voorbeelddata
///   genereren en alle data wissen.
///
/// Accounts, playbooks, confluence-beheer en overige instellingen volgen in
/// latere fases.
struct MoreView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var accounts: [Account]
    @Query private var trades: [Trade]
    @Query private var confluences: [Confluence]
    @Query private var instruments: [Instrument]

    @AppStorage(BackupSettings.Keys.lastBackupDate) private var lastBackupInterval: Double = 0

    @State private var isBusy = false
    @State private var showingCSVImport = false
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

                    Section("Data") {
                        NavigationLink {
                            BackupView()
                        } label: {
                            HStack {
                                Label("Backup & herstel", systemImage: "externaldrive")
                                Spacer()
                                if isBackupStale {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.warning)
                                }
                            }
                        }

                        Button {
                            showingCSVImport = true
                        } label: {
                            Label("CSV importeren", systemImage: "square.and.arrow.down.on.square")
                        }
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
            .sheet(isPresented: $showingCSVImport) {
                CSVImportView()
            }
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

    private var isBackupStale: Bool {
        BackupSettings.isStale(lastBackup: lastBackupInterval > 0 ? Date(timeIntervalSince1970: lastBackupInterval) : nil)
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
