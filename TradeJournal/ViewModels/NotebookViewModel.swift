import Foundation
import SwiftData

/// Notebook (SPEC §10): losse notities en lessen, te koppelen aan trades of
/// dagen. Houdt zoek-/filterstate vast en voert de mutaties uit.
@Observable
public final class NotebookViewModel {

    /// Bewerkbare velden van een notitie.
    public struct Draft: Equatable {
        public var title: String = ""
        public var body: String = ""
        public var isPinned: Bool = false
        public var linkedDate: Date? = nil
        public var tradeIDs: [UUID] = []

        public init(linkedDate: Date? = nil, tradeIDs: [UUID] = []) {
            self.linkedDate = linkedDate
            self.tradeIDs = tradeIDs
        }

        public init(from note: NotebookNote) {
            title = note.title
            body = note.body
            isPinned = note.isPinned
            linkedDate = note.linkedDate
            tradeIDs = note.trades.map(\.id)
        }

        public var isEmpty: Bool {
            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public var searchText: String = ""
    public var pinnedOnly: Bool = false

    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Lijst

    /// Gefilterd op zoektekst (titel, inhoud en symbolen van gekoppelde
    /// trades) en vastpinnen; vastgepinde notities eerst, daarna nieuwste eerst.
    public func filtered(_ notes: [NotebookNote]) -> [NotebookNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes
            .filter { !pinnedOnly || $0.isPinned }
            .filter { note in
                guard !query.isEmpty else { return true }
                return note.title.localizedCaseInsensitiveContains(query)
                    || note.body.localizedCaseInsensitiveContains(query)
                    || note.trades.contains { $0.symbol.localizedCaseInsensitiveContains(query) }
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    /// Notities gekoppeld aan een handelsdag.
    public func notes(linkedTo date: Date, from notes: [NotebookNote]) -> [NotebookNote] {
        filteredByRecency(notes.filter { note in
            note.linkedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        })
    }

    /// Notities gekoppeld aan een trade.
    public func notes(for trade: Trade) -> [NotebookNote] {
        filteredByRecency(trade.notebookNotes)
    }

    private func filteredByRecency(_ notes: [NotebookNote]) -> [NotebookNote] {
        notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Mutaties

    /// Maakt of werkt een notitie bij. Een lege nieuwe notitie wordt niet
    /// aangemaakt.
    @discardableResult
    public func save(_ draft: Draft, existing: NotebookNote?, allTrades: [Trade], in context: ModelContext, now: Date = Date()) -> NotebookNote? {
        if existing == nil, draft.isEmpty { return nil }
        let note = existing ?? NotebookNote(title: "", createdAt: now)
        if existing == nil { context.insert(note) }
        note.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        note.body = draft.body
        note.isPinned = draft.isPinned
        note.linkedDate = draft.linkedDate.map { calendar.startOfDay(for: $0) }
        let wanted = Set(draft.tradeIDs)
        note.trades = allTrades.filter { wanted.contains($0.id) }
        note.updatedAt = now
        return note
    }

    public func togglePin(_ note: NotebookNote) {
        note.isPinned.toggle()
    }

    public func delete(_ note: NotebookNote, in context: ModelContext) {
        context.delete(note)
    }
}
