import XCTest
import SwiftData
@testable import TradeJournal

/// Dashboards in de backup (export/restore, oude backups) en de
/// schemamigratie V1 → V2.
@MainActor
final class DashboardPersistenceTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DashboardPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    // MARK: - Backup

    func test_backupRoundTrip_restoresDashboardsWidgetsAndFilters() throws {
        let source = try makeContainer()
        let layout = DashboardLayoutService()
        layout.ensureDefaultDashboard(in: source.mainContext)
        let prop = layout.addDashboard(named: "Prop firm", in: source.mainContext)
        layout.saveFilters(DashboardFilterState(period: "thisWeek", symbolFilter: "ES"), for: prop, in: source.mainContext)
        let note = layout.addWidget(.note, size: .small, settings: WidgetSettings(customTitle: "Focus", noteText: "Geduld"), to: prop, in: source.mainContext)
        layout.addWidget(.yearHeatmap, size: .large, settings: WidgetSettings(heatmapMetric: .winRate), to: prop, in: source.mainContext)
        // Widget van een nieuwere app-versie blijft heel.
        let future = DashboardWidget(typeRaw: "future_widget", sizeRaw: "small", sortOrder: 9, settingsJSON: #"{"x":1}"#)
        source.mainContext.insert(future)
        future.dashboard = prop
        prop.widgets.append(future)
        try source.mainContext.save()

        let service = BackupService(settingsDefaults: nil)
        let url = try service.exportBackup(from: source.mainContext, to: directory)

        let target = try makeContainer()
        layout.ensureDefaultDashboard(in: target.mainContext)
        layout.addDashboard(named: "Wordt vervangen", in: target.mainContext)
        try service.restore(try service.loadBackup(at: url), into: target.mainContext)

        let restored = layout.dashboards(in: target.mainContext)
        XCTAssertEqual(restored.map(\.name), ["Overzicht", "Prop firm"])
        let restoredProp = try XCTUnwrap(restored.last)
        XCTAssertEqual(restoredProp.id, prop.id)
        XCTAssertEqual(restoredProp.filters.symbolFilter, "ES")
        XCTAssertEqual(restoredProp.filters.period, "thisWeek")
        XCTAssertEqual(restoredProp.sortedWidgets.map(\.typeRaw), ["note", "year_heatmap", "future_widget"])
        let restoredNote = try XCTUnwrap(restoredProp.sortedWidgets.first)
        XCTAssertEqual(restoredNote.id, note.id)
        XCTAssertEqual(restoredNote.settings.noteText, "Geduld")
        XCTAssertEqual(restoredNote.settings.customTitle, "Focus")
        XCTAssertEqual(restoredProp.sortedWidgets.last?.settingsJSON, #"{"x":1}"#)
        XCTAssertEqual(restored.first?.widgets.count, DashboardLayoutService.defaultLayout.count)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<Dashboard>()), 2)
    }

    /// Een backup van vóór het aanpasbare dashboard (geen `dashboards`) is
    /// nog steeds terug te zetten en laat de huidige indeling staan.
    func test_restoreOldBackupWithoutDashboards_keepsCurrentLayout() throws {
        let source = try makeContainer()
        source.mainContext.insert(Account(name: "Live", type: .live, startingBalance: 1_000))
        try source.mainContext.save()
        let service = BackupService(settingsDefaults: nil)
        let url = try service.exportBackup(from: source.mainContext, to: directory)

        // Payload terugbrengen naar het oude formaat: zonder `dashboards`.
        let data = try ZipReader(url: url).data(for: BackupService.payloadPath)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "dashboards")
        let oldURL = directory.appendingPathComponent("old.zip")
        let writer = try ZipWriter(url: oldURL)
        try writer.addFile(path: BackupService.payloadPath, data: try JSONSerialization.data(withJSONObject: json))
        try writer.finish()

        let loaded = try service.loadBackup(at: oldURL)
        XCTAssertNil(loaded.payload.dashboards)

        let target = try makeContainer()
        let layout = DashboardLayoutService()
        let custom = layout.addDashboard(named: "Mijn indeling", in: target.mainContext)
        layout.addWidget(.note, size: .small, to: custom, in: target.mainContext)
        try service.restore(loaded, into: target.mainContext)

        XCTAssertEqual(layout.dashboards(in: target.mainContext).map(\.name), ["Mijn indeling"])
        XCTAssertEqual(custom.widgets.count, 1)
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<Account>()).map(\.name), ["Live"])
    }

    func test_wipeAll_keepsDashboards() throws {
        let container = try makeContainer()
        DashboardLayoutService().ensureDefaultDashboard(in: container.mainContext)
        SampleDataService.wipeAll(in: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Dashboard>()), 1)
    }

    // MARK: - Migratie

    /// Een store van de vorige versie (schema V1, zonder dashboards) wordt met
    /// het migratieplan geopend; alle data blijft en de nieuwe modellen zijn
    /// bruikbaar.
    func test_migrationV1toV2_keepsDataAndAddsDashboardModels() throws {
        let storeURL = directory.appendingPathComponent("default.store")
        let tradeID = UUID()
        do {
            let v1 = Schema(versionedSchema: AppSchemaV1.self)
            let legacy = try ModelContainer(for: v1, configurations: [ModelConfiguration(schema: v1, url: storeURL)])
            let account = Account(name: "Topstep", type: .propFirm, startingBalance: 50_000)
            legacy.mainContext.insert(account)
            legacy.mainContext.insert(Trade(id: tradeID, symbol: "MNQ", direction: .long, entryDate: Date(), entryPrice: 0,
                                            quantity: 1, account: account, manualNetPnL: 46))
            try legacy.mainContext.save()
        }

        let upgraded = try PersistenceController.makeContainer(url: storeURL)
        let context = upgraded.mainContext
        let trades = try context.fetch(FetchDescriptor<Trade>())
        XCTAssertEqual(trades.map(\.id), [tradeID])
        XCTAssertEqual(trades.first?.manualNetPnL, 46)
        XCTAssertEqual(trades.first?.account?.name, "Topstep")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Dashboard>()), 0)

        SeedService.seedDashboardsIfNeeded(in: context, defaults: UserDefaults(suiteName: "DashboardPersistenceTests-\(UUID().uuidString)") ?? .standard)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Dashboard>()), 1)
        context.insert(TradeImportMark(tradeID: tradeID))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TradeImportMark>()), 1)

        // Geen herstelkopie nodig gehad: het plan opende de store direct.
        let recovery = directory.appendingPathComponent(PersistenceController.recoveryFolderName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.path), "migratie mislukte en viel terug")
    }

    func test_schemaVersions_areOrderedAndV2AddsOnlyNewModels() {
        XCTAssertEqual(AppMigrationPlan.schemas.count, 2)
        XCTAssertEqual(AppSchemaV1.models.count, AppSchema.v1Models.count)
        XCTAssertEqual(AppSchemaV2.models.count, AppSchema.v1Models.count + 3)
        XCTAssertEqual(AppMigrationPlan.stages.count, 1)
    }
}
