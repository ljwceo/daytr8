import Foundation
import SwiftData

/// Beheert dashboards en hun widgets: standaardindeling, tabbladen
/// aanmaken/hernoemen/verwijderen/verplaatsen en widgets toevoegen,
/// verwijderen, herordenen, van grootte wisselen en instellen.
///
/// Puur op een `ModelContext`, zonder UI, zodat alles unit-testbaar is.
/// Elke mutatie slaat de context direct op.
public struct DashboardLayoutService {

    /// Naam van het standaarddashboard.
    public static let defaultDashboardName = "Overzicht"

    /// Eén widget in een (standaard)indeling.
    public struct WidgetSpec: Equatable, Sendable {
        public let type: DashboardWidgetType
        public let size: WidgetSize
        public let settings: WidgetSettings

        public init(_ type: DashboardWidgetType, _ size: WidgetSize, _ settings: WidgetSettings = WidgetSettings()) {
            self.type = type
            self.size = size
            self.settings = settings
        }
    }

    /// De standaardindeling: dezelfde kaarten als het vaste dashboard van
    /// vóór de widgets (KPI's, doelen, score, grafieken, mini-kalender,
    /// recente trades), aangevuld met de jaar-heatmap.
    public static let defaultLayout: [WidgetSpec] = [
        WidgetSpec(.statistic, .small, WidgetSettings(metric: .netPnL)),
        WidgetSpec(.statistic, .small, WidgetSettings(metric: .winRate)),
        WidgetSpec(.statistic, .small, WidgetSettings(metric: .profitFactor)),
        WidgetSpec(.statistic, .small, WidgetSettings(metric: .expectancy)),
        WidgetSpec(.statistic, .small, WidgetSettings(metric: .averageWinLoss)),
        WidgetSpec(.statistic, .small, WidgetSettings(metric: .averageR)),
        WidgetSpec(.statistic, .small, WidgetSettings(metric: .largestWinLoss)),
        WidgetSpec(.statistic, .small, WidgetSettings(metric: .maxDrawdown)),
        WidgetSpec(.statistic, .small, WidgetSettings(metric: .streak)),
        WidgetSpec(.statistic, .small, WidgetSettings(metric: .tradeCount)),
        WidgetSpec(.goalProgress, .large),
        WidgetSpec(.tradingScore, .large),
        WidgetSpec(.yearHeatmap, .large),
        WidgetSpec(.equityCurve, .large),
        WidgetSpec(.dailyPnL, .large),
        WidgetSpec(.drawdown, .large),
        WidgetSpec(.miniCalendar, .large),
        WidgetSpec(.recentTrades, .large, WidgetSettings(itemCount: 5))
    ]

    public init() {}

    // MARK: - Dashboards

    /// Alle dashboards in tabvolgorde.
    public func dashboards(in context: ModelContext) -> [Dashboard] {
        let all = (try? context.fetch(FetchDescriptor<Dashboard>())) ?? []
        return all.sorted { lhs, rhs in
            lhs.sortOrder != rhs.sortOrder ? lhs.sortOrder < rhs.sortOrder : lhs.createdAt < rhs.createdAt
        }
    }

    /// Maakt het standaarddashboard aan als er nog geen enkel dashboard is
    /// (eerste start, of na een update vanaf de versie zonder widgets).
    /// `initialFilters`: de bewaarde filters van het oude dashboard, zodat
    /// die bij de overstap niet verloren gaan.
    /// - Returns: `true` als er iets is aangemaakt.
    @discardableResult
    public func ensureDefaultDashboard(in context: ModelContext, initialFilters: DashboardFilterState? = nil, now: Date = Date()) -> Bool {
        guard dashboards(in: context).isEmpty else { return false }
        let dashboard = Dashboard(name: Self.defaultDashboardName, sortOrder: 0, createdAt: now)
        if let initialFilters { dashboard.filters = initialFilters }
        context.insert(dashboard)
        insertWidgets(Self.defaultLayout, into: dashboard, in: context, now: now)
        save(context)
        return true
    }

    /// Nieuw, leeg dashboard achteraan.
    @discardableResult
    public func addDashboard(named name: String, in context: ModelContext, now: Date = Date()) -> Dashboard {
        let existing = dashboards(in: context)
        let dashboard = Dashboard(
            name: Self.cleanName(name, fallback: "Dashboard \(existing.count + 1)"),
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
            createdAt: now
        )
        context.insert(dashboard)
        save(context)
        return dashboard
    }

    public func rename(_ dashboard: Dashboard, to name: String, in context: ModelContext) {
        dashboard.name = Self.cleanName(name, fallback: dashboard.name)
        save(context)
    }

    /// Verwijdert een dashboard met zijn widgets. Het laatste dashboard blijft
    /// altijd staan.
    /// - Returns: `false` als het niet verwijderd mocht worden.
    @discardableResult
    public func delete(_ dashboard: Dashboard, in context: ModelContext) -> Bool {
        guard dashboards(in: context).count > 1 else { return false }
        context.delete(dashboard)
        save(context)
        normalizeDashboardOrder(in: context)
        return true
    }

    /// Schuift een tabblad `offset` plaatsen op (negatief = naar links).
    public func move(_ dashboard: Dashboard, by offset: Int, in context: ModelContext) {
        var ordered = dashboards(in: context)
        guard let index = ordered.firstIndex(where: { $0.id == dashboard.id }) else { return }
        let target = min(max(index + offset, 0), ordered.count - 1)
        guard target != index else { return }
        ordered.remove(at: index)
        ordered.insert(dashboard, at: target)
        for (order, item) in ordered.enumerated() { item.sortOrder = order }
        save(context)
    }

    public func saveFilters(_ state: DashboardFilterState, for dashboard: Dashboard, in context: ModelContext) {
        guard dashboard.filters != state else { return }
        dashboard.filters = state
        save(context)
    }

    // MARK: - Widgets

    @discardableResult
    public func addWidget(_ type: DashboardWidgetType, size: WidgetSize, settings: WidgetSettings = WidgetSettings(), to dashboard: Dashboard, in context: ModelContext, now: Date = Date()) -> DashboardWidget {
        let widget = DashboardWidget(type: type, size: size, settings: settings, sortOrder: (dashboard.widgets.map(\.sortOrder).max() ?? -1) + 1)
        widget.createdAt = now
        context.insert(widget)
        widget.dashboard = dashboard
        dashboard.widgets.append(widget)
        save(context)
        return widget
    }

    public func removeWidget(_ widget: DashboardWidget, in context: ModelContext) {
        let dashboard = widget.dashboard
        dashboard?.widgets.removeAll { $0.id == widget.id }
        context.delete(widget)
        if let dashboard { normalizeWidgetOrder(of: dashboard) }
        save(context)
    }

    /// Drag & drop: zet `widget` op de plek van `target` (de rest schuift op).
    public func moveWidget(_ widget: DashboardWidget, onto target: DashboardWidget, in context: ModelContext) {
        guard widget.id != target.id, let dashboard = widget.dashboard, target.dashboard?.id == dashboard.id else { return }
        var ordered = dashboard.sortedWidgets
        guard let from = ordered.firstIndex(where: { $0.id == widget.id }),
              let to = ordered.firstIndex(where: { $0.id == target.id }) else { return }
        ordered.remove(at: from)
        ordered.insert(widget, at: to)
        for (order, item) in ordered.enumerated() { item.sortOrder = order }
        save(context)
    }

    /// Schuift een widget `offset` plaatsen op (negatief = omhoog).
    public func moveWidget(_ widget: DashboardWidget, by offset: Int, in context: ModelContext) {
        guard let dashboard = widget.dashboard else { return }
        var ordered = dashboard.sortedWidgets
        guard let index = ordered.firstIndex(where: { $0.id == widget.id }) else { return }
        let target = min(max(index + offset, 0), ordered.count - 1)
        guard target != index else { return }
        ordered.remove(at: index)
        ordered.insert(widget, at: target)
        for (order, item) in ordered.enumerated() { item.sortOrder = order }
        save(context)
    }

    public func setSize(_ size: WidgetSize, of widget: DashboardWidget, in context: ModelContext) {
        widget.size = size
        save(context)
    }

    public func updateSettings(_ settings: WidgetSettings, of widget: DashboardWidget, in context: ModelContext) {
        widget.settings = settings
        save(context)
    }

    /// "Herstel standaardindeling": vervangt de widgets van `dashboard` door
    /// de standaardindeling. Naam en filters blijven staan.
    public func resetToDefault(_ dashboard: Dashboard, in context: ModelContext, now: Date = Date()) {
        for widget in dashboard.widgets { context.delete(widget) }
        dashboard.widgets = []
        insertWidgets(Self.defaultLayout, into: dashboard, in: context, now: now)
        save(context)
    }

    // MARK: - Raster

    /// Verdeelt widgets (in volgorde) over rijen: een grote widget krijgt een
    /// eigen rij, twee opeenvolgende kleine delen een rij. Een kleine widget
    /// zonder kleine buur staat alleen (halve breedte).
    /// - Returns: per rij de indexen in `sizes`.
    public static func rows(for sizes: [WidgetSize]) -> [[Int]] {
        var rows: [[Int]] = []
        var pending: Int?
        for (index, size) in sizes.enumerated() {
            switch size {
            case .large:
                if let waiting = pending {
                    rows.append([waiting])
                    pending = nil
                }
                rows.append([index])
            case .small:
                if let waiting = pending {
                    rows.append([waiting, index])
                    pending = nil
                } else {
                    pending = index
                }
            }
        }
        if let waiting = pending { rows.append([waiting]) }
        return rows
    }

    // MARK: - Helpers

    private func insertWidgets(_ specs: [WidgetSpec], into dashboard: Dashboard, in context: ModelContext, now: Date) {
        var widgets: [DashboardWidget] = []
        for (index, spec) in specs.enumerated() {
            let widget = DashboardWidget(type: spec.type, size: spec.size, settings: spec.settings, sortOrder: index)
            widget.createdAt = now
            context.insert(widget)
            widget.dashboard = dashboard
            widgets.append(widget)
        }
        dashboard.widgets = widgets
    }

    private func normalizeWidgetOrder(of dashboard: Dashboard) {
        for (order, item) in dashboard.sortedWidgets.enumerated() { item.sortOrder = order }
    }

    private func normalizeDashboardOrder(in context: ModelContext) {
        for (order, item) in dashboards(in: context).enumerated() { item.sortOrder = order }
        save(context)
    }

    static func cleanName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(40))
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("DashboardLayoutService.save error: \(error)")
            #endif
        }
    }
}
