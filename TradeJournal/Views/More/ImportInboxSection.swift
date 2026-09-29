import SwiftUI

/// Sectie voor Backup & herstel: backups die de gebruiker in Bestanden naar
/// "Op mijn iPhone › Daytr8 › Import" heeft gekopieerd. Werkt zonder
/// documentkiezer; tikken geeft de lokale URL door aan `onSelect`.
struct ImportInboxSection: View {

    @Environment(\.scenePhase) private var scenePhase

    @State private var candidates: [ImportCandidate] = []
    @State private var errorMessage: String?

    private let service: ImportInboxService
    private let onSelect: (URL) -> Void

    init(service: ImportInboxService = ImportInboxService(), onSelect: @escaping (URL) -> Void) {
        self.service = service
        self.onSelect = onSelect
    }

    var body: some View {
        Section {
            if candidates.isEmpty {
                Label("Nog geen backups in de map", systemImage: "tray")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(candidates) { candidate in
                    Button {
                        onSelect(candidate.url)
                    } label: {
                        row(for: candidate)
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }

            // De vernieuw-rij staat er altijd; daarom hangen het inlezen bij
            // openen en bij terugkeer naar de app hieraan (modifiers op de
            // Section zelf zou SwiftUI per rij herhalen).
            Button {
                refresh()
            } label: {
                Label("Vernieuw", systemImage: "arrow.clockwise")
                    .foregroundStyle(Theme.accent)
            }
            .onAppear { refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
        } header: {
            Text("Backups in de Daytr8-map")
        } footer: {
            Text("In Bestanden: houd de backup ingedrukt → Kopieer → Op mijn iPhone › Daytr8 › Import → Plak. Een uitgepakte map kopiëren kan ook; dan komen de screenshots mee.")
        }
        .listRowBackground(Theme.card)
    }

    private func row(for candidate: ImportCandidate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: candidate))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(candidate.modified.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .contentShape(Rectangle())
    }

    private func icon(for candidate: ImportCandidate) -> String {
        if candidate.isFolder { return "folder" }
        return candidate.url.pathExtension.lowercased() == "json" ? "doc.text" : "doc.zipper"
    }

    private func refresh() {
        do {
            try service.ensureFolder()
            errorMessage = nil
        } catch {
            errorMessage = "Importmap kon niet worden aangemaakt: \(error.localizedDescription)"
        }
        candidates = service.scan()
    }
}

#Preview {
    NavigationStack {
        List {
            ImportInboxSection { _ in }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}
