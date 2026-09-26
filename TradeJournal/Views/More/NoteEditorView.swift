import SwiftUI
import SwiftData

/// Aanmaken/bewerken van een notebook-notitie, met koppeling aan een dag en
/// aan trades.
struct NoteEditorView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Trade.entryDate, order: .reverse) private var allTrades: [Trade]

    let note: NotebookNote?

    @State private var viewModel = NotebookViewModel()
    @State private var draft: NotebookViewModel.Draft
    @State private var showingTradePicker = false

    init(note: NotebookNote?, linkedDate: Date? = nil, linkedTrade: Trade? = nil) {
        self.note = note
        if let note {
            _draft = State(initialValue: NotebookViewModel.Draft(from: note))
        } else {
            _draft = State(initialValue: NotebookViewModel.Draft(
                linkedDate: linkedDate ?? linkedTrade.map { $0.exitDate ?? $0.entryDate },
                tradeIDs: linkedTrade.map { [$0.id] } ?? []
            ))
        }
    }

    private var linkedTrades: [Trade] {
        let ids = Set(draft.tradeIDs)
        return allTrades.filter { ids.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $draft.title)
                        .font(.headline)
                    TextField("Notitie of les…", text: $draft.body, axis: .vertical)
                        .lineLimit(6...30)
                    Toggle("Vastpinnen", isOn: $draft.isPinned)
                }
                .listRowBackground(Theme.card)

                Section("Gekoppelde dag") {
                    Toggle("Koppel aan een dag", isOn: hasLinkedDate)
                    if draft.linkedDate != nil {
                        DatePicker("Dag", selection: linkedDateBinding, displayedComponents: .date)
                    }
                }
                .listRowBackground(Theme.card)

                Section("Gekoppelde trades") {
                    ForEach(linkedTrades) { trade in
                        HStack {
                            tradeLabel(trade)
                            Spacer()
                            Button {
                                draft.tradeIDs.removeAll { $0 == trade.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(Theme.loss)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        showingTradePicker = true
                    } label: {
                        Label("Trade koppelen", systemImage: "link")
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(note == nil ? "Nieuwe notitie" : "Notitie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        viewModel.save(draft, existing: note, allTrades: allTrades, in: modelContext)
                        dismiss()
                    }
                    .disabled(note == nil && draft.isEmpty)
                }
            }
            .sheet(isPresented: $showingTradePicker) {
                TradeLinkPickerView(trades: allTrades, selectedIDs: $draft.tradeIDs)
            }
        }
    }

    private var hasLinkedDate: Binding<Bool> {
        Binding(
            get: { draft.linkedDate != nil },
            set: { draft.linkedDate = $0 ? (draft.linkedDate ?? Date()) : nil }
        )
    }

    private var linkedDateBinding: Binding<Date> {
        Binding(
            get: { draft.linkedDate ?? Date() },
            set: { draft.linkedDate = $0 }
        )
    }

    private func tradeLabel(_ trade: Trade) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(trade.symbol) · \(trade.direction.displayName)")
                .font(.subheadline.weight(.medium))
            Text(trade.entryDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Lijst met trades (doorzoekbaar op symbool) om aan een notitie te koppelen.
private struct TradeLinkPickerView: View {

    @Environment(\.dismiss) private var dismiss

    let trades: [Trade]
    @Binding var selectedIDs: [UUID]

    @State private var searchText = ""

    /// Begrensd tot de meest recente 300 resultaten, zodat de lijst ook bij
    /// tienduizenden trades snel blijft.
    private var visibleTrades: [Trade] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? trades : trades.filter { $0.symbol.localizedCaseInsensitiveContains(query) }
        return Array(matching.prefix(300))
    }

    var body: some View {
        NavigationStack {
            List(visibleTrades) { trade in
                Button {
                    toggle(trade)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(trade.symbol) · \(trade.direction.displayName)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text(trade.entryDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if selectedIDs.contains(trade.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $searchText, prompt: "Zoek op symbool")
            .navigationTitle("Trades koppelen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ trade: Trade) {
        if let index = selectedIDs.firstIndex(of: trade.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(trade.id)
        }
    }
}
