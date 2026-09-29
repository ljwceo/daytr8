import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Backup & herstel (SPEC §9): handmatige zip-backup via de share sheet,
/// volledige restore, automatische backup naar een map in Bestanden en
/// CSV-export van alle trades.
struct BackupView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = BackupViewModel()
    /// Toont de iOS-documentkiezer via UIKit (i.p.v. `.fileImporter`, dat op
    /// het toestel niet betrouwbaar terugriep).
    @State private var picker = DocumentPickerPresenter()
    /// Backup die uit de importmap gekozen is; na een geslaagde restore
    /// verhuist hij naar `Import/Hersteld/`.
    @State private var inboxSelection: URL?
    /// Wijzigt na een restore, zodat de importmap-sectie opnieuw scant.
    @State private var inboxRefreshID = UUID()

    var body: some View {
        List {
            // Meldingen bovenaan, zodat ze na het kiezen van een bestand direct
            // in beeld zijn (onderaan vielen ze buiten beeld).
            if let message = viewModel.errorMessage {
                Section {
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(Theme.loss)
                        .font(.footnote)
                }
                .listRowBackground(Theme.card)
            } else if let message = viewModel.statusMessage {
                Section {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.profit)
                        .font(.footnote)
                }
                .listRowBackground(Theme.card)
            }

            pendingRestoreSection
            statusSection
            backupSection
            restoreSection
            // Importmap "Op mijn iPhone › Daytr8 › Import" (werkt zonder kiezer).
            ImportInboxSection { url in
                inboxSelection = url
                viewModel.diagnostics.record("Importmap: backup gekozen", detail: url.lastPathComponent)
                Task { await viewModel.prepareRestore(from: url) }
            }
            .id(inboxRefreshID)
            autoBackupSection
            exportSection
            diagnosticsSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Backup & herstel")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(viewModel.isWorking)
        .overlay {
            if viewModel.isWorking {
                ProgressView()
                    .padding(Theme.cardPadding)
                    .background(RoundedRectangle(cornerRadius: Theme.smallCornerRadius).fill(Theme.elevated))
            }
        }
        .onAppear { viewModel.refreshFromSettings() }
        .sheet(item: $viewModel.shareFile, onDismiss: {
            viewModel.shareSheetDismissed()
        }) { file in
            ActivityShareSheet(items: [file.url]) { completed in
                viewModel.shareSheetFinished(completed: completed)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Backup herstellen?",
            isPresented: $viewModel.isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Wis huidige data en herstel", role: .destructive) {
                viewModel.confirmRestore(into: modelContext)
                markInboxBackupRestoredIfNeeded()
            }
            Button("Annuleren", role: .cancel) {
                viewModel.cancelRestore()
            }
        } message: {
            Text(restoreMessage)
        }
    }

    // MARK: - Secties

    private var statusSection: some View {
        Section {
            HStack {
                Text("Laatste backup")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(viewModel.lastBackupDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Nooit")
                    .foregroundStyle(viewModel.isBackupStale ? Theme.warning : Theme.textSecondary)
            }
            Toggle("Backupherinnering tonen", isOn: Binding(
                get: { !viewModel.isReminderDismissed },
                set: { viewModel.setReminderEnabled($0) }
            ))
            if viewModel.isBackupStale {
                Label("Maak regelmatig een backup: bij opnieuw signen of een ingetrokken certificaat kan lokale data verloren gaan.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        } header: {
            Text("Status")
        } footer: {
            Text("De herinnering verschijnt op het dashboard als de laatste backup ouder is dan 7 dagen.")
        }
        .listRowBackground(Theme.card)
    }

    private var backupSection: some View {
        Section {
            Button {
                viewModel.createBackup(from: modelContext)
            } label: {
                Label("Backup maken (.zip)", systemImage: "externaldrive.badge.plus")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Bevat alle trades, accounts, playbooks, confluences, journals en screenshots. Kies \"Bewaar in Bestanden\" of deel het bestand, bijvoorbeeld naar je computer.")
        }
        .listRowBackground(Theme.card)
    }

    /// De gekozen, al ingelezen backup — bovenaan, zodat hij na het sluiten van
    /// de bestandskiezer direct in beeld is. Bewust geen automatisch dialoog-
    /// venster: dat opent SwiftUI niet zolang de bestandskiezer nog sluit
    /// ("er gebeurt niks" na het kiezen).
    @ViewBuilder
    /// Na een geslaagde restore uit de importmap: backup naar `Import/Hersteld/`.
    private func markInboxBackupRestoredIfNeeded() {
        guard let url = inboxSelection else { return }
        inboxSelection = nil
        guard viewModel.errorMessage == nil, viewModel.pendingRestore == nil else { return }
        if let moved = try? ImportInboxService().markRestored(url: url) {
            viewModel.diagnostics.record("Importmap: backup verplaatst naar Hersteld", detail: moved.lastPathComponent)
        }
        inboxRefreshID = UUID()
    }

    private var pendingRestoreSection: some View {
        if let summary = viewModel.pendingRestore?.summary {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Backup gevonden", systemImage: "doc.zipper")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(summaryText(summary))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Button(role: .destructive) {
                    viewModel.isConfirmingRestore = true
                } label: {
                    Label("Herstel deze backup…", systemImage: "arrow.counterclockwise.circle.fill")
                }
                Button("Annuleren") {
                    viewModel.cancelRestore()
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    private var restoreSection: some View {
        Section {
            Button(role: .destructive) {
                pick(.backupFile, action: "Herstel uit backupbestand") { url in
                    Task { await viewModel.prepareRestore(from: url, isTemporaryCopy: true) }
                }
            } label: {
                Label("Herstel uit backupbestand…", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) {
                pick(.folder, action: "Herstel uit uitgepakte backupmap") { url in
                    Task { await viewModel.prepareRestore(from: url) }
                }
            } label: {
                Label("Herstel uit uitgepakte backupmap…", systemImage: "folder")
            }
        } header: {
            Text("Herstellen")
        } footer: {
            Text("Backupbestand: kies de .zip of, als Bestanden de zip al heeft uitgepakt, de backup.json daaruit. Uitgepakte backupmap: kies de map met backup.json en images — dan komen ook de screenshots mee. Een restore vervangt álle huidige data door de inhoud van de backup; je ziet eerst een samenvatting ter bevestiging.")
        }
        .listRowBackground(Theme.card)
    }

    private var autoBackupSection: some View {
        Section {
            if let folder = viewModel.autoBackupFolderName {
                HStack {
                    Label(folder, systemImage: "folder.fill")
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("Wijzig") {
                        pickAutoBackupFolder(action: "Wijzig backupmap")
                    }
                }

                Picker("Frequentie", selection: Binding(
                    get: { viewModel.autoBackupFrequency },
                    set: { viewModel.setAutoBackupFrequency($0) }
                )) {
                    ForEach(AutoBackupFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }

                Button {
                    viewModel.runAutoBackupNow(from: modelContext)
                } label: {
                    Label("Nu backuppen naar map", systemImage: "arrow.down.doc")
                }

                if let error = viewModel.lastAutoBackupError {
                    Label("Laatste automatische backup mislukt: \(error)", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }

                if let last = viewModel.lastAutoBackupDate {
                    HStack {
                        Text("Laatste automatische backup")
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .font(.footnote)
                }

                Button("Map loskoppelen", role: .destructive) {
                    viewModel.clearAutoBackupFolder()
                }
            } else {
                Button {
                    pickAutoBackupFolder(action: "Kies backupmap")
                } label: {
                    Label("Kies backupmap in Bestanden…", systemImage: "folder.badge.plus")
                }
            }
        } header: {
            Text("Automatische backup")
        } footer: {
            Text(viewModel.hasAutoBackupFolder
                 ? "De app schrijft bij het openen (of dagelijks) een backup naar de gekozen map en bewaart daar de laatste \(BackupSettings.defaultKeepCount) automatische backups."
                 : "Staat uit tot je een map kiest (bijv. iCloud Drive of Op mijn iPhone). Na het kiezen wordt er direct een eerste backup gemaakt.")
        }
        .listRowBackground(Theme.card)
    }

    private var exportSection: some View {
        Section {
            Button {
                viewModel.exportCSV(from: modelContext)
            } label: {
                Label("Trades exporteren als CSV", systemImage: "tablecells")
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Eén rij per trade, inclusief P&L, R-multiple, confluences en notities. Dit bestand kan later ook weer geïmporteerd worden.")
        }
        .listRowBackground(Theme.card)
    }

    private var diagnosticsSection: some View {
        Section {
            NavigationLink {
                ImportLogView(log: viewModel.diagnostics)
            } label: {
                Label("Importlogboek", systemImage: "list.bullet.rectangle")
            }
        } header: {
            Text("Diagnose")
        } footer: {
            Text("Lukt herstellen niet? Deel het importlogboek: daarin staat elke stap van het kiezen en inlezen.\n\(ImportDiagnosticsLog.appVersionDescription)")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Bestandskiezer

    /// Opent de documentkiezer; `onPick` krijgt de gekozen URL. Annuleren en
    /// een kiezer die niet opent komen als melding bovenaan.
    @MainActor
    private func pick(_ mode: DocumentPickerPresenter.Mode, action: String, onPick: @escaping (URL) -> Void) {
        viewModel.recordPickerRequest(action)
        do {
            try picker.present(mode) { url in
                if let url {
                    onPick(url)
                } else {
                    viewModel.pickerCancelled()
                }
            }
        } catch {
            viewModel.pickerFailed(error)
        }
    }

    @MainActor
    private func pickAutoBackupFolder(action: String) {
        pick(.folder, action: action) { url in
            // Volgende runloop-tik: de kiezer sluit eerst.
            Task { @MainActor in viewModel.setAutoBackupFolder(url, context: modelContext) }
        }
    }

    private func summaryText(_ summary: BackupService.Summary) -> String {
        let date = summary.exportedAt.formatted(date: .abbreviated, time: .shortened)
        return "Backup van \(date): \(summary.tradeCount) trades, \(summary.accountCount) accounts, "
            + "\(summary.playbookCount) playbooks, \(summary.journalCount) journals, \(summary.screenshotCount) screenshots."
    }

    private var restoreMessage: String {
        guard let summary = viewModel.pendingRestore?.summary else { return "" }
        return summaryText(summary) + "\n\nAlle huidige data wordt gewist en vervangen. Dit kan niet ongedaan gemaakt worden."
    }
}

#Preview {
    NavigationStack {
        BackupView()
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
    .preferredColorScheme(.dark)
}
