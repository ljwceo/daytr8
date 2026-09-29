import SwiftUI
import SwiftData

/// Een backup die via de Bestanden-app of het deelmenu naar de app gestuurd
/// is (zie `IncomingFileRouter`). Leest hem in, toont een samenvatting en
/// herstelt na bevestiging — los van de bestandskiezer in `BackupView`.
struct IncomingBackupView: View {

    let url: URL

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = BackupViewModel()
    @State private var hasLoaded = false

    /// Hersteld in dit scherm: de viewmodel meldt succes en heeft geen
    /// wachtende backup meer.
    private var isRestored: Bool {
        viewModel.pendingRestore == nil && viewModel.statusMessage != nil
    }

    var body: some View {
        List {
            Section {
                Label(url.lastPathComponent, systemImage: "doc.zipper")
                    .foregroundStyle(Theme.textPrimary)
                    .font(.subheadline)
            } header: {
                Text("Bestand")
            }
            .listRowBackground(Theme.card)

            if !hasLoaded || viewModel.isWorking {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(hasLoaded ? "Bezig met herstellen…" : "Backup inlezen…")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.card)
            }

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
                        dismiss()
                    }
                } footer: {
                    Text("Een restore vervangt álle huidige data door de inhoud van deze backup.")
                }
                .listRowBackground(Theme.card)
            }

            if isRestored {
                Section {
                    Button("Sluiten") { dismiss() }
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Backup openen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(isRestored ? "Sluiten" : "Annuleren") {
                    if !isRestored { viewModel.cancelRestore() }
                    dismiss()
                }
                .disabled(viewModel.isWorking)
            }
        }
        .interactiveDismissDisabled(viewModel.isWorking)
        .task {
            guard !hasLoaded else { return }
            await viewModel.prepareRestore(from: url)
            hasLoaded = true
        }
        .confirmationDialog(
            "Backup herstellen?",
            isPresented: $viewModel.isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Wis huidige data en herstel", role: .destructive) {
                viewModel.confirmRestore(into: modelContext)
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text(restoreMessage)
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
