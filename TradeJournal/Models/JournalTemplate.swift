import Foundation
import SwiftData

/// Bewerkbare template voor het daily journal (pre-market plan of
/// post-market review). De standaardtemplate per soort wordt in
/// `DayDetailView` met één tik in het bijbehorende veld gezet.
///
/// De tekst mag de placeholder `{{datum}}` bevatten; die wordt bij het
/// toepassen vervangen door de datum van de handelsdag
/// (zie `JournalTemplateService.render`).
@Model
public final class JournalTemplate {

    public var id: UUID = UUID()

    /// Ruwe waarde van `JournalTemplateKind`. Gebruik `kind` in code.
    public var kindRaw: String = JournalTemplateKind.preMarket.rawValue

    public var name: String = ""

    /// De template-tekst (markdown / plain text).
    public var body: String = ""

    /// Precies één template per soort is de standaard.
    public var isDefault: Bool = false

    public var isBuiltIn: Bool = false
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        kind: JournalTemplateKind,
        name: String,
        body: String,
        isDefault: Bool = false,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.name = name
        self.body = body
        self.isDefault = isDefault
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var kind: JournalTemplateKind {
        get { JournalTemplateKind(rawValue: kindRaw) ?? .preMarket }
        set { kindRaw = newValue.rawValue }
    }
}
