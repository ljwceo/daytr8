import SwiftUI
import SwiftData

/// "Meer"-tab.
///
/// - Journal (fase 6): progress tracker, notebook en journal-templates.
/// - Accounts & doelen (fase 6): accounts met maanddoel, daily loss limit en
///   max drawdown; backtest-accounts.
/// - Trading: beheer van confluences (toevoegen, bewerken, archiveren,
///   verwijderen).
/// - Instellingen (fase 6): journal-herinnering en app-slot; fase 7:
///   overzicht van de screenshot-templates; thema en "Rondleiding opnieuw
///   bekijken" (onboarding).
/// - Data: backup & herstel (incl. automatische backup en CSV-export) en
///   CSV-import (fase 5).
/// - Debug-tools uit fase 1: standaarddata seeden, ~2 jaar voorbeelddata
///   genereren en alle data wissen.
struct MoreView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var accounts: [Account]
    @Query private var trades: [Trade]
    @Query private var confluences: [Confluence]
    @Query private var instruments: [Instrument]

    @Environment(AppLockViewModel.self) private var appLock
    @Environment(OnboardingViewModel.self) private var onboarding

    @AppStorage(BackupSettings.Keys.lastBackupDate) private var lastBackupInterval: Double = 0
    @AppStorage(BackupSettings.Keys.reminderDismissed) private var isReminderDismissed = false

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

                    Section("Journal") {
                        NavigationLink {
                            ProgressTrackerView()
                        } label: {
                            Label("Progress tracker", systemImage: "flame")
                        }
                        NavigationLink {
                            NotebookView()
                        } label: {
                            Label("Notebook", systemImage: "note.text")
                        }
                        NavigationLink {
                            JournalTemplatesView()
                        } label: {
                            Label("Journal-templates", systemImage: "doc.text")
                        }
                    }

                    Section("Accounts") {
                        NavigationLink {
                            AccountsView()
                        } label: {
                            Label("Accounts & doelen", systemImage: "person.crop.circle")
                        }
                    }

                    Section("Trading") {
                        NavigationLink {
                            ConfluencesView()
                        } label: {
                            Label("Confluences", systemImage: "checklist")
                        }
                    }

                    Section("Instellingen") {
                        NavigationLink {
                            ThemeSettingsView()
                        } label: {
                            Label(AppStrings.Themes.settingsTitle, systemImage: "paintpalette")
                        }
                        Button {
                            onboarding.startTour()
                        } label: {
                            Label(AppStrings.Settings.replayTour, systemImage: "sparkles")
                        }
                        NavigationLink {
                            ReminderSettingsView()
                        } label: {
                            Label("Herinneringen", systemImage: "bell")
                        }
                        NavigationLink {
                            AppLockSettingsView(viewModel: appLock)
                        } label: {
                            Label("App-slot", systemImage: "lock")
                        }
                        NavigationLink {
                            ScreenshotTemplatesView()
                        } label: {
                            Label("Screenshot-templates", systemImage: "text.viewfinder")
                        }
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
                            lastMessage = "Standaarddata ingeschoten (confluences alleen als er nog geen enkele is)."
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
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background)

                if isBusy {
                    ProgressView("Bezig…")
                        .padding(Theme.cardPadding)
                        .background(Theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
            }
            .navigationTitle("Meer")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingCSVImport) {
                CSVImportView()
            }
            // Resultaat van een debug-actie als pop-up: onderaan de lijst viel
            // de melding buiten beeld.
            .alert(
                lastMessage ?? "",
                isPresented: Binding(get: { lastMessage != nil }, set: { if !$0 { lastMessage = nil } })
            ) {
                Button("OK", role: .cancel) { lastMessage = nil }
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
        BackupSettings.shouldShowReminder(
            lastBackup: lastBackupInterval > 0 ? Date(timeIntervalSince1970: lastBackupInterval) : nil,
            dismissed: isReminderDismissed
        )
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
        .environment(AppLockViewModel())
        .environment(OnboardingViewModel())
        .modelContainer(for: AppSchema.models, inMemory: true)
        .preferredColorScheme(.dark)
}
