import XCTest
import SwiftData
@testable import TradeJournal

/// Presets en instellingen overleven een herstart en een app-update
/// (SwiftData-store op schijf + versiebeheer van instellingen).
@MainActor
final class PersistenceTests: XCTestCase {

    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("default.store") }
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "PersistenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try super.tearDownWithError()
    }

    // MARK: - SwiftData op schijf

    /// Preset aanmaken → app "herstarten" (nieuwe container op dezelfde store)
    /// → preset bestaat nog; de seed bij de start overschrijft niets.
    func test_presetsSurviveRestart_andSeedDoesNotOverwrite() throws {
        do {
            let container = try PersistenceController.makeContainer(url: storeURL)
            let context = container.mainContext
            SeedService.seedDefaultsIfNeeded(in: context, defaults: defaults)

            context.insert(Playbook(name: "London sweep"))
            context.insert(Confluence(name: "Mijn eigen confluence", category: .other))
            context.insert(Account(name: "Live account", type: .live, startingBalance: 10_000, dailyLossLimit: 500, monthlyProfitTarget: 2_000))

            // Gebruiker past een standaardconfluence aan en verwijdert een instrumentpreset.
            let confluences = try context.fetch(FetchDescriptor<Confluence>())
            let edited = try XCTUnwrap(confluences.first { $0.isBuiltIn })
            edited.name = "Hernoemd door gebruiker"
            let mes = try XCTUnwrap(try context.fetch(FetchDescriptor<Instrument>()).first { $0.symbol == "MES" })
            context.delete(mes)
            try context.save()
        }

        // Herstart.
        let container = try PersistenceController.makeContainer(url: storeURL)
        let context = container.mainContext
        SeedService.seedDefaultsIfNeeded(in: context, defaults: defaults)

        let playbooks = try context.fetch(FetchDescriptor<Playbook>())
        XCTAssertEqual(playbooks.map(\.name), ["London sweep"])
        let confluences = try context.fetch(FetchDescriptor<Confluence>())
        XCTAssertTrue(confluences.contains { $0.name == "Mijn eigen confluence" })
        XCTAssertTrue(confluences.contains { $0.name == "Hernoemd door gebruiker" })
        XCTAssertEqual(confluences.count, DefaultConfluences.all.count + 1)
        let account = try XCTUnwrap(try context.fetch(FetchDescriptor<Account>()).first)
        XCTAssertEqual(account.monthlyProfitTarget, 2_000)
        XCTAssertEqual(account.dailyLossLimit, 500)
        let instruments = try context.fetch(FetchDescriptor<Instrument>())
        XCTAssertFalse(instruments.contains { $0.symbol == "MES" }, "verwijderde preset komt niet terug")
        XCTAssertEqual(instruments.count, InstrumentPresets.all.count - 1)
    }

    /// Versie-upgrade: een store van de vorige app-versie (zonder versiebeheer)
    /// wordt door de nieuwe versie (met `AppMigrationPlan`) gewoon geopend.
    func test_upgradeFromUnversionedStore_keepsAllData() throws {
        let tradeID = UUID()
        do {
            let schema = Schema(AppSchema.models)
            let legacy = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
            let context = legacy.mainContext
            let account = Account(name: "Topstep", type: .propFirm, startingBalance: 50_000, monthlyProfitTarget: 3_000)
            context.insert(account)
            context.insert(Playbook(name: "NY open"))
            context.insert(Trade(id: tradeID, symbol: "MNQ", direction: .long, entryDate: Date(), entryPrice: 0,
                                 quantity: 1, account: account, manualNetPnL: 46))
            try context.save()
        }

        let upgraded = try PersistenceController.makeContainer(url: storeURL)
        let context = upgraded.mainContext
        let trades = try context.fetch(FetchDescriptor<Trade>())
        XCTAssertEqual(trades.map(\.id), [tradeID])
        XCTAssertEqual(trades.first?.manualNetPnL, 46)
        XCTAssertEqual(trades.first?.account?.name, "Topstep")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Playbook>()).map(\.name), ["NY open"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Account>()).first?.monthlyProfitTarget, 3_000)
    }

    func test_backupStoreFiles_copiesWithoutDeleting() throws {
        try Data("store".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))
        let folder = try XCTUnwrap(PersistenceController.backupStoreFiles(at: storeURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("default.store")), Data("store".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("default.store-wal").path))
    }

    // MARK: - Instellingen: versies en migraties

    func test_settingsMigrator_freshInstall_setsCurrentVersion() {
        XCTAssertEqual(SettingsMigrator.migrateIfNeeded(defaults: defaults), [1])
        XCTAssertEqual(defaults.integer(forKey: SettingsMigrator.Keys.schemaVersion), SettingsMigrator.currentVersion)
        // Tweede start: niets meer te doen.
        XCTAssertEqual(SettingsMigrator.migrateIfNeeded(defaults: defaults), [])
    }

    /// Upgrade van een versie zonder versiebeheer: alle instellingen blijven.
    func test_settingsMigrator_legacyValuesArePreserved() {
        defaults.set("mint", forKey: ThemeStore.Keys.selectedPaletteID)
        defaults.set(8, forKey: ReminderSettings.Keys.hour)
        defaults.set(true, forKey: CalendarViewModel.includeBacktestKey)

        SettingsMigrator.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(ThemeStore(defaults: defaults).palette.id, "mint")
        XCTAssertEqual(ReminderSettings(defaults: defaults).hour, 8)
        XCTAssertTrue(defaults.bool(forKey: CalendarViewModel.includeBacktestKey))
    }

    /// Gesimuleerde toekomstige versie die een sleutel hernoemt: de oude
    /// waarde wordt omgezet, niet weggegooid, en een bestaande nieuwe waarde
    /// wint van de oude.
    func test_settingsMigrator_futureRenameMigration() {
        defaults.set(1, forKey: SettingsMigrator.Keys.schemaVersion)
        defaults.set("perzik", forKey: "theme.palette")          // oude sleutel
        defaults.set("oud", forKey: "reminder.text")
        defaults.set("nieuw", forKey: ReminderSettings.Keys.message)

        let migrations = SettingsMigrator.migrations + [
            SettingsMigrator.Migration(version: 2) { defaults in
                SettingsMigrator.renameKey("theme.palette", to: ThemeStore.Keys.selectedPaletteID, in: defaults)
                SettingsMigrator.renameKey("reminder.text", to: ReminderSettings.Keys.message, in: defaults)
            }
        ]
        XCTAssertEqual(SettingsMigrator.migrateIfNeeded(defaults: defaults, migrations: migrations), [2])

        XCTAssertEqual(defaults.string(forKey: ThemeStore.Keys.selectedPaletteID), "perzik")
        XCTAssertNil(defaults.object(forKey: "theme.palette"))
        XCTAssertEqual(ReminderSettings(defaults: defaults).message, "nieuw")
        XCTAssertEqual(defaults.integer(forKey: SettingsMigrator.Keys.schemaVersion), 2)
    }

    func test_settingsMigrator_newerStoredVersionIsLeftAlone() {
        defaults.set(99, forKey: SettingsMigrator.Keys.schemaVersion)
        XCTAssertEqual(SettingsMigrator.migrateIfNeeded(defaults: defaults), [])
        XCTAssertEqual(defaults.integer(forKey: SettingsMigrator.Keys.schemaVersion), 99)
    }

    // MARK: - Filters en importkoppelingen

    func test_dashboardFilters_surviveRestart() {
        let accountID = UUID()
        let first = DashboardViewModel(filterSettings: DashboardFilterSettings(defaults: defaults))
        first.period = .thisMonth
        first.selectedAccountIDs = [accountID]
        first.symbolFilter = "MNQ"
        first.includeBacktest = true
        first.saveFilters()

        let restarted = DashboardViewModel(filterSettings: DashboardFilterSettings(defaults: defaults))
        XCTAssertEqual(restarted.period, .thisMonth)
        XCTAssertEqual(restarted.selectedAccountIDs, [accountID])
        XCTAssertEqual(restarted.symbolFilter, "MNQ")
        XCTAssertTrue(restarted.includeBacktest)

        restarted.pruneFilters(accountIDs: [], playbookIDs: [], confluenceIDs: [])
        XCTAssertTrue(restarted.selectedAccountIDs.isEmpty)

        // Zonder opgeslagen filters: standaardwaarden.
        let fresh = DashboardViewModel(filterSettings: DashboardFilterSettings(defaults: UserDefaults(suiteName: "leeg-\(UUID().uuidString)")!))
        XCTAssertEqual(fresh.period, .all)
    }

    func test_csvMapping_isRememberedPerHeader() throws {
        let headers = ["Ticker", "Wanneer", "Koers"]
        let mapping = CSVColumnMapping(mode: .trades, columns: [.symbol: 0, .entryTime: 1, .entryPrice: 2], dateOrder: .dayFirst, timeZoneIdentifier: "Europe/Amsterdam")
        CSVMappingStore(defaults: defaults).save(mapping, for: headers)

        XCTAssertEqual(CSVMappingStore(defaults: defaults).mapping(for: [" ticker", "WANNEER", "Koers "]), mapping)
        XCTAssertNil(CSVMappingStore(defaults: defaults).mapping(for: ["Ticker"]))

        let viewModel = CSVImportViewModel(mappingStore: CSVMappingStore(defaults: defaults))
        viewModel.load(data: Data("Ticker,Wanneer,Koers\nNQ,05-12-2024 10:00,21000\n".utf8), fileName: "eigen.csv")
        XCTAssertEqual(viewModel.mapping, mapping)
    }

    // MARK: - Instellingen in de backup

    func test_settingsSnapshot_roundTripsThroughBackup() throws {
        defaults.set("lavendel", forKey: ThemeStore.Keys.selectedPaletteID)
        defaults.set(9, forKey: ReminderSettings.Keys.hour)
        defaults.set(true, forKey: ReminderSettings.Keys.isEnabled)
        defaults.set(0.5, forKey: AppLockService.Keys.gracePeriod)
        defaults.set(Data([1, 2, 3]), forKey: BackupSettings.Keys.autoBackupFolderBookmark)   // toestelgebonden
        SettingsMigrator.migrateIfNeeded(defaults: defaults)

        let schema = Schema(AppSchema.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let url = try BackupService(settingsDefaults: defaults).exportBackup(from: container.mainContext, to: directory)

        let targetSuite = "PersistenceTests-target-\(UUID().uuidString)"
        let target = try XCTUnwrap(UserDefaults(suiteName: targetSuite))
        defer { target.removePersistentDomain(forName: targetSuite) }
        let service = BackupService(settingsDefaults: target)
        let loaded = try service.loadBackup(at: url)
        XCTAssertEqual(loaded.payload.settings?[ThemeStore.Keys.selectedPaletteID], .string("lavendel"))
        XCTAssertNil(loaded.payload.settings?[BackupSettings.Keys.autoBackupFolderBookmark])
        try service.restore(loaded, into: container.mainContext)

        XCTAssertEqual(ThemeStore(defaults: target).palette.id, "lavendel")
        XCTAssertEqual(ReminderSettings(defaults: target).hour, 9)
        XCTAssertTrue(ReminderSettings(defaults: target).isEnabled)
        XCTAssertEqual(target.double(forKey: AppLockService.Keys.gracePeriod), 0.5)
        XCTAssertNil(target.data(forKey: BackupSettings.Keys.autoBackupFolderBookmark))
    }

    func test_settingValue_readsDefaultsTypes() {
        XCTAssertEqual(SettingValue(defaultsObject: true), .bool(true))
        XCTAssertEqual(SettingValue(defaultsObject: 17), .int(17))
        XCTAssertEqual(SettingValue(defaultsObject: 1.5), .double(1.5))
        XCTAssertEqual(SettingValue(defaultsObject: "x"), .string("x"))
        XCTAssertNil(SettingValue(defaultsObject: Data()))
        XCTAssertNil(SettingValue(defaultsObject: nil))
    }
}
