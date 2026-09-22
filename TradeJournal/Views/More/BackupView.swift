import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Backup & herstel (SPEC §9): handmatige zip-backup via de share sheet,
/// volledige restore, automatische backup naar een map in Bestanden en
/// CSV-export van alle trades.
struct BackupView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = BackupViewModel()
    @State private var importerKind: ImporterKind = .restore
    @State private var isImporterPresented = false

    /// Eén `fileImporter` voor zowel backup-bestanden als mappen: meerdere
    /// `fileImporter`s op dezelfde view werken in SwiftUI niet betrouwbaar.
    private enum ImporterKind {
        case restore
        case folder

        var contentTypes: [UTType] {
            switch self {
            case .restore: return [.zip]
            case .folder: return [.folder]
            }
        }
    }

    var body: some View {
        List {
            statusSection
            backupSection
            restoreSection
            autoBackupSection
            exportSection

            if let message = viewModel.errorMessage {
                Section {
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(Theme.loss)
                        .font(.footnote)
                }
            } else if let message = viewModel.statusMessage {
                Section {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.profit)
                        .font(.footnote)
                }
            }
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
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: importerKind.contentTypes) { result in
            switch result {
            case .success(let url):
                switch importerKind {
                case .restore: viewModel.prepareRestore(from: url)
                case .folder: viewModel.setAutoBackupFolder(url)
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $viewModel.shareFile, onDismiss: {
            viewModel.shareSheetFinished(completed: false)
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
            if viewModel.isBackupStale {
                Label("Maak regelmatig een backup: bij opnieuw signen of een ingetrokken certificaat kan lokale data verloren gaan.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        } header: {
            Text("Status")
        }
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
    }

    private var restoreSection: some View {
        Section {
            Button(role: .destructive) {
                importerKind = .restore
                isImporterPresented = true
            } label: {
                Label("Herstel uit backup…", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Herstellen")
        } footer: {
            Text("Een restore vervangt álle huidige data door de inhoud van de backup. Je ziet eerst een samenvatting ter bevestiging.")
        }
    }

    private var autoBackupSection: some View {
        Section {
            if let folder = viewModel.autoBackupFolderName {
                HStack {
                    Label(folder, systemImage: "folder.fill")
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("Wijzig") {
                        importerKind = .folder
                        isImporterPresented = true
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
                    importerKind = .folder
                    isImporterPresented = true
                } label: {
                    Label("Kies backupmap in Bestanden…", systemImage: "folder.badge.plus")
                }
            }
        } header: {
            Text("Automatische backup")
        } footer: {
            Text("De app schrijft een backup naar de gekozen map (bijv. iCloud Drive of Op mijn iPhone) en bewaart daar de laatste \(BackupSettings.defaultKeepCount) automatische backups.")
        }
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
    }

    private var restoreMessage: String {
        guard let summary = viewModel.pendingRestore?.summary else { return "" }
        let date = summary.exportedAt.formatted(date: .abbreviated, time: .shortened)
        return """
        Backup van \(date): \(summary.tradeCount) trades, \(summary.accountCount) accounts, \
        \(summary.playbookCount) playbooks, \(summary.journalCount) journals, \(summary.screenshotCount) screenshots.

        Alle huidige data wordt gewist en vervangen. Dit kan niet ongedaan gemaakt worden.
        """
    }
}

#Preview {
    NavigationStack {
        BackupView()
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
    .preferredColorScheme(.dark)
}
