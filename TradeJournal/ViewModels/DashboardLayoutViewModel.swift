import Foundation
import SwiftData

/// Bewerkstatus en acties van het aanpasbare dashboard: welk tabblad open
/// staat, de bewerkmodus en alle wijzigingen aan dashboards en widgets
/// (via `DashboardLayoutService`). De view muteert zelf niets.
@Observable
public final class DashboardLayoutViewModel {

    /// Het geopende dashboard; `nil` = het eerste.
    public var selectedDashboardID: UUID?
    public var isEditing = false

    public let service: DashboardLayoutService

    /// Onthoudt het laatst geopende tabblad (alleen een weergavevoorkeur).
    @ObservationIgnored private let defaults: UserDefaults?
    public static let selectedDashboardKey = "dashboard.selectedDashboardID"

    public init(service: DashboardLayoutService = DashboardLayoutService(), defaults: UserDefaults? = .standard) {
        self.service = service
        self.defaults = defaults
        if let raw = defaults?.string(forKey: Self.selectedDashboardKey) {
            selectedDashboardID = UUID(uuidString: raw)
        }
    }

    /// Het geopende dashboard uit `dashboards` (val terug op het eerste).
    public func selectedDashboard(in dashboards: [Dashboard]) -> Dashboard? {
        dashboards.first { $0.id == selectedDashboardID } ?? dashboards.first
    }

    public func select(_ dashboard: Dashboard) {
        selectedDashboardID = dashboard.id
        defaults?.set(dashboard.id.uuidString, forKey: Self.selectedDashboardKey)
    }

    // MARK: - Dashboards

    public func ensureDefault(in context: ModelContext) {
        service.ensureDefaultDashboard(in: context, initialFilters: DashboardFilterSettings().load())
    }

    @discardableResult
    public func addDashboard(named name: String, in context: ModelContext) -> Dashboard {
        let dashboard = service.addDashboard(named: name, in: context)
        select(dashboard)
        return dashboard
    }

    public func rename(_ dashboard: Dashboard, to name: String, in context: ModelContext) {
        service.rename(dashboard, to: name, in: context)
    }

    public func delete(_ dashboard: Dashboard, in context: ModelContext) {
        let wasSelected = dashboard.id == selectedDashboardID
        guard service.delete(dashboard, in: context) else { return }
        if wasSelected, let first = service.dashboards(in: context).first { select(first) }
    }

    public func move(_ dashboard: Dashboard, by offset: Int, in context: ModelContext) {
        service.move(dashboard, by: offset, in: context)
    }

    public func saveFilters(_ state: DashboardFilterState, for dashboard: Dashboard, in context: ModelContext) {
        service.saveFilters(state, for: dashboard, in: context)
    }

    public func resetToDefault(_ dashboard: Dashboard, in context: ModelContext) {
        service.resetToDefault(dashboard, in: context)
    }

    // MARK: - Widgets

    public func addWidget(_ type: DashboardWidgetType, size: WidgetSize, settings: WidgetSettings, to dashboard: Dashboard, in context: ModelContext) {
        service.addWidget(type, size: size, settings: settings, to: dashboard, in: context)
    }

    public func removeWidget(_ widget: DashboardWidget, in context: ModelContext) {
        service.removeWidget(widget, in: context)
    }

    public func toggleSize(of widget: DashboardWidget, in context: ModelContext) {
        service.setSize(widget.size.toggled, of: widget, in: context)
    }

    public func update(_ widget: DashboardWidget, settings: WidgetSettings, size: WidgetSize, in context: ModelContext) {
        if widget.size != size { service.setSize(size, of: widget, in: context) }
        service.updateSettings(settings, of: widget, in: context)
    }

    /// Drag & drop: het gesleepte widget-id op de plek van `target`.
    @discardableResult
    public func drop(widgetID: String, onto target: DashboardWidget, in dashboard: Dashboard, context: ModelContext) -> Bool {
        guard let id = UUID(uuidString: widgetID),
              let dragged = dashboard.widgets.first(where: { $0.id == id }),
              dragged.id != target.id else { return false }
        service.moveWidget(dragged, onto: target, in: context)
        return true
    }

    public func moveWidget(_ widget: DashboardWidget, by offset: Int, in context: ModelContext) {
        service.moveWidget(widget, by: offset, in: context)
    }
}
