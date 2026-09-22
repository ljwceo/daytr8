import SwiftUI
import SwiftData

/// Beheer van de daily journal-templates (pre-market en post-market review).
/// De standaardtemplate per soort is in het dagjournal met één tik in te voegen.
struct JournalTemplatesView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \JournalTemplate.sortOrder) private var templates: [JournalTemplate]

    @State private var editorTarget: EditorTarget?

    private let service = JournalTemplateService()

    private struct EditorTarget: Identifiable {
        let id = UUID()
        let kind: JournalTemplateKind
        let template: JournalTemplate?
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                ForEach(JournalTemplateKind.allCases) { kind in
                    Section {
                        ForEach(service.sorted(templates.filter { $0.kind == kind })) { template in
                            Button {
                                editorTarget = EditorTarget(kind: kind, template: template)
                            } label: {
                                row(template)
                            }
                            .swipeActions(edge: .leading) {
                                if !template.isDefault {
                                    Button {
                                        service.setDefault(template, in: modelContext)
                                    } label: {
                                        Label("Standaard", systemImage: "star")
                                    }
                                    .tint(Theme.accent)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    service.delete(template, in: modelContext)
                                } label: {
                                    Label("Verwijderen", systemImage: "trash")
                                }
                            }
                        }
                        Button {
                            editorTarget = EditorTarget(kind: kind, template: nil)
                        } label: {
                            Label("Nieuwe template", systemImage: "plus")
                        }
                    } header: {
                        Text(kind.displayName)
                    }
                }

                Section {
                    Text("Gebruik \(JournalTemplateService.datePlaceholder) om de datum van de handelsdag in te vullen. Veeg naar rechts om een template de standaard te maken.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Journal-templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $editorTarget) { target in
            JournalTemplateEditorView(kind: target.kind, template: target.template)
        }
    }

    private func row(_ template: JournalTemplate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(template.name.isEmpty ? "Naamloos" : template.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if template.isDefault {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            Text(template.body)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
    }
}

/// Sheet om een template te maken of te bewerken.
private struct JournalTemplateEditorView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let kind: JournalTemplateKind
    let template: JournalTemplate?

    @State private var name: String
    @State private var bodyText: String

    private let service = JournalTemplateService()

    init(kind: JournalTemplateKind, template: JournalTemplate?) {
        self.kind = kind
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _bodyText = State(initialValue: template?.body ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Naam") {
                    TextField("Naam", text: $name)
                }
                Section("Template") {
                    TextField("Vragen / kopjes…", text: $bodyText, axis: .vertical)
                        .lineLimit(8...40)
                        .font(.body.monospaced())
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(template == nil ? "Nieuwe \(kind.displayName.lowercased())-template" : "Template bewerken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        if let template {
                            service.update(template, name: name, body: bodyText)
                        } else {
                            service.create(kind: kind, name: name, body: bodyText, in: modelContext)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
