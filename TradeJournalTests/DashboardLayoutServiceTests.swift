import XCTest
import SwiftData
@testable import TradeJournal

/// Dashboards en widgets: standaardindeling, tabbladen, toevoegen,
/// verwijderen, herordenen, grootte, instellingen en het raster.
@MainActor
final class DashboardLayoutServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let service = DashboardLayoutService()

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func types(_ dashboard: Dashboard) -> [DashboardWidgetType?] {
        dashboard.sortedWidgets.map(\.type)
    }

    // MARK: - Standaardindeling

    func test_ensureDefault_createsOverviewWithDefaultLayout_once() throws {
        let filters = DashboardFilterState(period: "thisMonth", includeBacktest: true)
        XCTAssertTrue(service.ensureDefaultDashboard(in: context, initialFilters: filters))
        XCTAssertFalse(service.ensureDefaultDashboard(in: context), "tweede keer niets")

        let dashboards = service.dashboards(in: context)
        XCTAssertEqual(dashboards.map(\.name), [DashboardLayoutService.defaultDashboardName])
        let dashboard = try XCTUnwrap(dashboards.first)
        XCTAssertEqual(types(dashboard), DashboardLayoutService.defaultLayout.map(\.type))
        XCTAssertEqual(dashboard.sortedWidgets.map(\.sortOrder), Array(0..<DashboardLayoutService.defaultLayout.count))
        XCTAssertEqual(dashboard.filters, filters, "filters van het oude dashboard gaan mee")
        XCTAssertEqual(dashboard.sortedWidgets.first?.settings.metric, .netPnL)
    }

    func test_defaultLayout_containsEveryOldDashboardCard_andHeatmap() {
        let types = Set(DashboardLayoutService.defaultLayout.map(\.type))
        for expected: DashboardWidgetType in [.statistic, .goalProgress, .tradingScore, .equityCurve, .dailyPnL, .drawdown, .miniCalendar, .recentTrades, .yearHeatmap] {
            XCTAssertTrue(types.contains(expected), "\(expected) ontbreekt")
        }
    }

    func test_seedService_seedsDashboard_andKeepsUserLayout() throws {
        let suite = "DashboardLayoutServiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        DashboardFilterSettings(defaults: defaults).save(DashboardFilterState(symbolFilter: "NQ"))

        SeedService.seedDefaultsIfNeeded(in: context, defaults: defaults)
        let dashboard = try XCTUnwrap(service.dashboards(in: context).first)
        XCTAssertEqual(dashboard.filters.symbolFilter, "NQ")

        service.removeWidget(try XCTUnwrap(dashboard.sortedWidgets.first), in: context)
        let remaining = dashboard.widgets.count
        SeedService.seedDefaultsIfNeeded(in: context, defaults: defaults)
        XCTAssertEqual(service.dashboards(in: context).count, 1)
        XCTAssertEqual(dashboard.widgets.count, remaining, "seed overschrijft de indeling niet")
    }

    // MARK: - Dashboards

    func test_addRenameMoveDelete_dashboards() throws {
        service.ensureDefaultDashboard(in: context)
        let prop = service.addDashboard(named: "  Prop firm  ", in: context)
        let backtest = service.addDashboard(named: "", in: context)
        XCTAssertEqual(service.dashboards(in: context).map(\.name), ["Overzicht", "Prop firm", "Dashboard 3"])
        XCTAssertTrue(prop.widgets.isEmpty, "nieuw dashboard begint leeg")

        service.rename(backtest, to: "Backtest", in: context)
        service.move(backtest, by: -2, in: context)
        XCTAssertEqual(service.dashboards(in: context).map(\.name), ["Backtest", "Overzicht", "Prop firm"])

        XCTAssertTrue(service.delete(prop, in: context))
        XCTAssertEqual(service.dashboards(in: context).map(\.name), ["Backtest", "Overzicht"])
        XCTAssertEqual(service.dashboards(in: context).map(\.sortOrder), [0, 1])
    }

    func test_lastDashboard_cannotBeDeleted() throws {
        service.ensureDefaultDashboard(in: context)
        let only = try XCTUnwrap(service.dashboards(in: context).first)
        XCTAssertFalse(service.delete(only, in: context))
        XCTAssertEqual(service.dashboards(in: context).count, 1)
    }

    func test_deletingDashboard_deletesItsWidgets() throws {
        service.ensureDefaultDashboard(in: context)
        let extra = service.addDashboard(named: "Extra", in: context)
        service.addWidget(.note, size: .small, to: extra, in: context)
        let before = try context.fetchCount(FetchDescriptor<DashboardWidget>())
        XCTAssertTrue(service.delete(extra, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DashboardWidget>()), before - 1)
    }

    func test_eachDashboardHasOwnFilters() throws {
        service.ensureDefaultDashboard(in: context)
        let overview = try XCTUnwrap(service.dashboards(in: context).first)
        let prop = service.addDashboard(named: "Prop firm", in: context)
        let accountID = UUID()
        service.saveFilters(DashboardFilterState(selectedAccountIDs: [accountID], period: "thisWeek"), for: prop, in: context)

        XCTAssertEqual(prop.filters.selectedAccountIDs, [accountID])
        XCTAssertEqual(prop.filters.period, "thisWeek")
        XCTAssertEqual(overview.filters, DashboardFilterState())
    }

    // MARK: - Widgets

    func test_addRemoveResizeAndSettings() throws {
        let dashboard = service.addDashboard(named: "Test", in: context)
        let note = service.addWidget(.note, size: .small, to: dashboard, in: context)
        let heatmap = service.addWidget(.yearHeatmap, size: .large, settings: WidgetSettings(heatmapMetric: .rMultiple), to: dashboard, in: context)
        XCTAssertEqual(types(dashboard), [.note, .yearHeatmap])
        XCTAssertEqual(heatmap.settings.heatmapMetric, .rMultiple)

        service.setSize(.large, of: note, in: context)
        XCTAssertEqual(note.size, .large)

        var settings = note.settings
        settings.noteText = "Max 2 trades per dag"
        settings.customTitle = "Focus"
        service.updateSettings(settings, of: note, in: context)
        XCTAssertEqual(note.settings.noteText, "Max 2 trades per dag")
        XCTAssertEqual(note.settings.customTitle, "Focus")

        service.removeWidget(note, in: context)
        XCTAssertEqual(types(dashboard), [.yearHeatmap])
        XCTAssertEqual(dashboard.sortedWidgets.map(\.sortOrder), [0])
    }

    func test_dragAndDrop_movesWidgetOntoTarget() throws {
        let dashboard = service.addDashboard(named: "Test", in: context)
        let a = service.addWidget(.note, size: .small, to: dashboard, in: context)
        let b = service.addWidget(.statistic, size: .small, to: dashboard, in: context)
        let c = service.addWidget(.equityCurve, size: .large, to: dashboard, in: context)

        service.moveWidget(c, onto: a, in: context)
        XCTAssertEqual(dashboard.sortedWidgets.map(\.id), [c.id, a.id, b.id])

        service.moveWidget(c, onto: b, in: context)
        XCTAssertEqual(dashboard.sortedWidgets.map(\.id), [a.id, b.id, c.id])

        service.moveWidget(a, by: 1, in: context)
        XCTAssertEqual(dashboard.sortedWidgets.map(\.id), [b.id, a.id, c.id])
        service.moveWidget(b, by: -1, in: context)
        XCTAssertEqual(dashboard.sortedWidgets.map(\.id), [b.id, a.id, c.id], "bovenste kan niet hoger")
    }

    func test_layoutViewModel_drop_usesWidgetID() throws {
        let viewModel = DashboardLayoutViewModel(defaults: nil)
        let dashboard = viewModel.addDashboard(named: "Test", in: context)
        XCTAssertEqual(viewModel.selectedDashboardID, dashboard.id)
        viewModel.addWidget(.note, size: .small, settings: WidgetSettings(), to: dashboard, in: context)
        viewModel.addWidget(.backupStatus, size: .small, settings: WidgetSettings(), to: dashboard, in: context)
        let widgets = dashboard.sortedWidgets
        XCTAssertTrue(viewModel.drop(widgetID: widgets[1].id.uuidString, onto: widgets[0], in: dashboard, context: context))
        XCTAssertEqual(types(dashboard), [.backupStatus, .note])
        XCTAssertFalse(viewModel.drop(widgetID: "geen-uuid", onto: widgets[0], in: dashboard, context: context))

        viewModel.toggleSize(of: widgets[0], in: context)
        XCTAssertEqual(widgets[0].size, .large)
    }

    func test_resetToDefault_replacesWidgets_keepsNameAndFilters() throws {
        let dashboard = service.addDashboard(named: "Prop firm", in: context)
        service.saveFilters(DashboardFilterState(symbolFilter: "ES"), for: dashboard, in: context)
        service.addWidget(.note, size: .small, to: dashboard, in: context)

        service.resetToDefault(dashboard, in: context)
        XCTAssertEqual(types(dashboard), DashboardLayoutService.defaultLayout.map(\.type))
        XCTAssertEqual(dashboard.name, "Prop firm")
        XCTAssertEqual(dashboard.filters.symbolFilter, "ES")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DashboardWidget>()), DashboardLayoutService.defaultLayout.count)
    }

    // MARK: - Raster

    func test_rows_pairSmallWidgets_largeWidgetsGetOwnRow() {
        XCTAssertEqual(DashboardLayoutService.rows(for: [.small, .small, .large, .small, .large, .small, .small, .small]),
                       [[0, 1], [2], [3], [4], [5, 6], [7]])
        XCTAssertEqual(DashboardLayoutService.rows(for: []), [])
        XCTAssertEqual(DashboardLayoutService.rows(for: [.large, .large]), [[0], [1]])
    }

    // MARK: - Instellingen

    func test_widgetSettings_roundTripAndTolerantDecoding() {
        let settings = WidgetSettings(customTitle: "Mijn P&L", period: .custom, customStart: Date(timeIntervalSince1970: 1_000),
                                      customEnd: Date(timeIntervalSince1970: 90_000), accountIDs: [UUID()], metric: .profitFactor,
                                      heatmapMetric: .winRate, dimension: .confluence, itemCount: 4, noteText: "x")
        XCTAssertEqual(WidgetSettings.from(json: settings.jsonString), settings)

        // Onbekende waardes en velden (nieuwere app-versie) → standaard, niet kapot.
        let future = #"{"metric":"sharpe_ratio","period":"quarter","itemCount":7,"somethingNew":true}"#
        let decoded = WidgetSettings.from(json: future)
        XCTAssertEqual(decoded.metric, .netPnL)
        XCTAssertEqual(decoded.period, .dashboard)
        XCTAssertEqual(decoded.itemCount, 7)
        XCTAssertEqual(WidgetSettings.from(json: "kapot"), WidgetSettings())
    }

    func test_unknownWidgetType_isKept() {
        let widget = DashboardWidget(typeRaw: "future_widget", sizeRaw: "huge")
        XCTAssertNil(widget.type)
        XCTAssertEqual(widget.size, .large)
        XCTAssertEqual(widget.typeRaw, "future_widget")
    }

    // MARK: - Registry

    func test_registry_hasDefinitionForEveryType() {
        for type in DashboardWidgetType.allCases {
            let definition = DashboardWidgetRegistry.definition(for: type)
            XCTAssertNotNil(definition, "\(type) heeft geen definitie")
            if let definition {
                XCTAssertFalse(definition.title.isEmpty)
                XCTAssertFalse(definition.supportedSizes.isEmpty)
                XCTAssertTrue(definition.supportedSizes.contains(definition.defaultSize))
            }
        }
        XCTAssertEqual(DashboardWidgetRegistry.definitions.count, DashboardWidgetType.allCases.count)
        for spec in DashboardLayoutService.defaultLayout {
            let definition = DashboardWidgetRegistry.definition(for: spec.type)
            XCTAssertEqual(definition?.effectiveSize(spec.size), spec.size, "\(spec.type) in de standaardindeling heeft een ondersteunde grootte")
        }
    }
}
