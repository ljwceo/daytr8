import Foundation
import SwiftData

/// Eén dashboard (tabblad op de Dashboard-tab), bijv. "Overzicht", "Prop firm"
/// of "Backtest", met eigen filters en een eigen set widgets.
@Model
public final class Dashboard {

    public var id: UUID = UUID()
    public var name: String = ""
    /// Volgorde van de tabbladen (laag = links).
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()

    /// Filters van dit dashboard (`DashboardFilterState` als JSON). Leeg =
    /// geen filters (alles).
    public var filtersJSON: String = ""

    @Relationship(deleteRule: .cascade, inverse: \DashboardWidget.dashboard)
    public var widgets: [DashboardWidget] = []

    public init(id: UUID = UUID(), name: String, sortOrder: Int = 0, createdAt: Date = Date(), filtersJSON: String = "") {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.filtersJSON = filtersJSON
    }

    /// Widgets in weergavevolgorde.
    public var sortedWidgets: [DashboardWidget] {
        widgets.sorted { lhs, rhs in
            lhs.sortOrder != rhs.sortOrder ? lhs.sortOrder < rhs.sortOrder : lhs.createdAt < rhs.createdAt
        }
    }

    /// Getypte toegang tot `filtersJSON`.
    public var filters: DashboardFilterState {
        get {
            guard let data = filtersJSON.data(using: .utf8),
                  let state = try? JSONDecoder().decode(DashboardFilterState.self, from: data) else {
                return DashboardFilterState()
            }
            return state
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue), let text = String(data: data, encoding: .utf8) else { return }
            filtersJSON = text
        }
    }
}
