import Foundation
import SwiftData

/// Losse notitie of les in het notebook. Kan optioneel gekoppeld worden aan
/// een handelsdag (`linkedDate`) en/of aan één of meer trades.
@Model
public final class NotebookNote {

    public var id: UUID = UUID()
    public var title: String = ""

    /// Inhoud (markdown / plain text).
    public var body: String = ""

    /// Vastgepinde notities staan bovenaan het notebook.
    public var isPinned: Bool = false

    /// Optionele koppeling aan een handelsdag (middernacht, gebruikers-tijdzone).
    public var linkedDate: Date? = nil

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    /// Gekoppelde trades (many-to-many).
    @Relationship(inverse: \Trade.notebookNotes)
    public var trades: [Trade] = []

    public init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        isPinned: Bool = false,
        linkedDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isPinned = isPinned
        self.linkedDate = linkedDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Titel voor lijsten: valt terug op de eerste regel van de inhoud.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let line = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? "Naamloze notitie" : line
    }
}
