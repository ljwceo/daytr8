import Foundation
import SwiftData

/// Vrije label die aan trades gekoppeld kan worden (many-to-many).
@Model
public final class Tag {

    public var id: UUID = UUID()
    public var name: String = ""
    public var colorHex: String = "#4C8BF5"
    public var isBuiltIn: Bool = false
    public var createdAt: Date = Date()

    @Relationship(inverse: \Trade.tags)
    public var trades: [Trade] = []

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#4C8BF5",
        isBuiltIn: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }
}
