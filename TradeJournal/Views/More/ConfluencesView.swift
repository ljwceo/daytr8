import SwiftUI
import SwiftData

/// Beheer van confluences: toevoegen, bewerken, archiveren, sorteren
/// (binnen een categorie) en verwijderen, plus de standaardset terugzetten.
struct ConfluencesView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Confluence.sortOrder) private var confluences: [Confluence]

    @State private var viewModel = ConfluenceSettingsViewModel()
    @State private var editorTarget: EditorTarget?
    @State private var pendingDelete: Confluence?
    @State private var message: String?

    /// Welke confluence de editor-sheet bewerkt (`nil` = nieuw).
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let confluence: Confluence?
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                ForEach(ConfluenceCategory.allCases) { category in
                    let items = confluences.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(category.displayName) {
                            ForEach(items) { confluence in
                                Button {
                                    editorTarget = EditorTarget(confluence: confluence)
                                } label: {
                                    row(confluence)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = confluence
                                    } label: {
                                        Label("Verwijderen", systemImage: "trash")
                                    }
                                    Button {
                                        viewModel.setActive(confluence, !confluence.isActive)
                                    } label: {
                                        Label(confluence.isActive ? "Archiveren" : "Activeren",
                                              systemImage: confluence.isActive ? "archivebox" : "tray.and.arrow.up")
                                    }
                                    .tint(Theme.neutral)
                                }
                            }
                            .onMove { source, destination in
                                viewModel.move(items, from: source, to: destination)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        let count = viewModel.restoreDefaults(in: modelContext)
                        message = count == 0
                            ? "Alle standaardconfluences zijn al aanwezig."
                            : "\(count) standaardconfluence(s) teruggezet."
                    } label: {
                        Label("Standaardset terugzetten", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Tik op een confluence om hem te bewerken; veeg naar links om te archiveren of te verwijderen. Gearchiveerde confluences verschijnen niet meer in nieuwe trades, maar blijven op bestaande trades en in de rapporten staan.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Confluences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = EditorTarget(confluence: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(item: $editorTarget) { target in
            ConfluenceEditorView(confluence: target.confluence, all: confluences, viewModel: viewModel)
        }
        .confirmationDialog(
            "\(pendingDelete?.name ?? "Confluence") verwijderen?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { confluence in
            Button("Verwijderen", role: .destructive) {
                viewModel.delete(confluence, in: modelContext)
                pendingDelete = nil
            }
            if confluence.isActive {
                Button("Archiveren") {
                    viewModel.setActive(confluence, false)
                    pendingDelete = nil
                }
            }
            Button("Annuleren", role: .cancel) { pendingDelete = nil }
        } message: { confluence in
            Text(deleteMessage(confluence))
        }
        .alert(
            message ?? "",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("OK", role: .cancel) { message = nil }
        }
    }

    private func row(_ confluence: Confluence) -> some View {
        HStack(spacing: 12) {
            Image(systemName: confluence.iconName)
                .foregroundStyle(Color(hex: confluence.colorHex))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(confluence.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(confluence.isActive ? Theme.textPrimary : Theme.textTertiary)
                if let subtitle = subtitle(confluence) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .opacity(confluence.isActive ? 1 : 0.7)
    }

    private func subtitle(_ confluence: Confluence) -> String? {
        var parts: [String] = []
        if !confluence.isBuiltIn { parts.append("eigen") }
        if !confluence.isActive { parts.append("gearchiveerd") }
        if !confluence.trades.isEmpty { parts.append("\(confluence.trades.count) trades") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func deleteMessage(_ confluence: Confluence) -> String {
        let count = confluence.trades.count
        if count == 0 { return "Deze actie kan niet ongedaan gemaakt worden." }
        return "Deze confluence staat op \(count) trade(s) en verdwijnt daar en uit de rapporten. Archiveren houdt hem op bestaande trades."
    }
}

/// Sheet om één confluence aan te maken of te bewerken.
private struct ConfluenceEditorView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let confluence: Confluence?
    let all: [Confluence]
    let viewModel: ConfluenceSettingsViewModel

    @State private var draft: ConfluenceSettingsViewModel.Draft

    init(confluence: Confluence?, all: [Confluence], viewModel: ConfluenceSettingsViewModel) {
        self.confluence = confluence
        self.all = all
        self.viewModel = viewModel
        _draft = State(initialValue: confluence.map(ConfluenceSettingsViewModel.Draft.init(from:)) ?? ConfluenceSettingsViewModel.Draft())
    }

    private var nameError: String? {
        viewModel.nameError(for: draft, existing: confluence, all: all)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Naam (bijv. Sweep PDL)", text: $draft.name)
                    Picker("Categorie", selection: $draft.category) {
                        ForEach(ConfluenceCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    Toggle("Actief", isOn: $draft.isActive)
                } header: {
                    Text("Confluence")
                } footer: {
                    if let nameError, !draft.trimmedName.isEmpty {
                        Text(nameError).foregroundStyle(Theme.warning)
                    }
                }

                Section("Voorbeeld") {
                    ChipView(title: draft.trimmedName.isEmpty ? "Confluence" : draft.trimmedName,
                             systemImage: draft.iconName,
                             color: Color(hex: draft.colorHex),
                             isSelected: true)
                        .listRowBackground(Theme.card)
                }

                Section("Kleur") {
                    FlowLayout(spacing: 10) {
                        ForEach(ConfluenceSettingsViewModel.colorOptions, id: \.self) { hex in
                            Button {
                                draft.colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle().stroke(Theme.textPrimary, lineWidth: draft.colorHex.lowercased() == hex.lowercased() ? 2 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icoon") {
                    FlowLayout(spacing: 8) {
                        ForEach(ConfluenceSettingsViewModel.iconOptions, id: \.self) { icon in
                            Button {
                                draft.iconName = icon
                            } label: {
                                Image(systemName: icon)
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(draft.iconName == icon ? Theme.textPrimary : Theme.textSecondary)
                                    .background(draft.iconName == icon ? Color(hex: draft.colorHex).opacity(0.85) : Theme.elevated)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Omschrijving") {
                    TextField("Optioneel", text: $draft.descriptionText, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(confluence == nil ? "Nieuwe confluence" : "Confluence bewerken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        viewModel.save(draft, existing: confluence, all: all, in: modelContext)
                        dismiss()
                    }
                    .disabled(nameError != nil)
                }
            }
            .onChange(of: draft.category) { oldCategory, newCategory in
                // Volgde de kleur de categorie, dan meeveranderen.
                if draft.colorHex.lowercased() == oldCategory.defaultColorHex.lowercased() {
                    draft.colorHex = newCategory.defaultColorHex
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ConfluencesView()
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
    .preferredColorScheme(.dark)
}
