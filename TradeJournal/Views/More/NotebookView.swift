import SwiftUI
import SwiftData

/// Notebook (SPEC §10): losse notities en lessen, doorzoekbaar, vast te
/// pinnen en te koppelen aan trades of dagen.
struct NotebookView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \NotebookNote.updatedAt, order: .reverse) private var notes: [NotebookNote]

    @State private var viewModel = NotebookViewModel()
    @State private var editorTarget: NoteEditorTarget?

    var body: some View {
        let visible = viewModel.filtered(notes)

        return ZStack {
            Theme.background.ignoresSafeArea()
            List {
                if visible.isEmpty {
                    Text(notes.isEmpty
                         ? "Nog geen notities. Leg lessen, observaties en ideeën vast en koppel ze aan trades of dagen."
                         : "Geen notities gevonden.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.card)
                }
                ForEach(visible) { note in
                    Button {
                        editorTarget = NoteEditorTarget(note: note)
                    } label: {
                        NoteRowView(note: note)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            viewModel.togglePin(note)
                        } label: {
                            Label(note.isPinned ? "Losmaken" : "Vastpinnen", systemImage: note.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(Theme.warning)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.delete(note, in: modelContext)
                        } label: {
                            Label("Verwijderen", systemImage: "trash")
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $viewModel.searchText, prompt: "Zoek in notities")
        }
        .navigationTitle("Notebook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.pinnedOnly.toggle()
                } label: {
                    Image(systemName: viewModel.pinnedOnly ? "pin.fill" : "pin")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = NoteEditorTarget(note: nil)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            NoteEditorView(note: target.note, linkedDate: target.linkedDate, linkedTrade: target.linkedTrade)
        }
    }
}

/// Wat de notitie-editor opent: een bestaande notitie, of een nieuwe
/// (optioneel al gekoppeld aan een dag of trade).
struct NoteEditorTarget: Identifiable {
    let id = UUID()
    var note: NotebookNote?
    var linkedDate: Date? = nil
    var linkedTrade: Trade? = nil
}
