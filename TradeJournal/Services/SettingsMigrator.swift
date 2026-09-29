import Foundation

/// Versiebeheer en migraties voor de instellingen in `UserDefaults`
/// (thema, herinneringen, filters, importkoppelingen, ...).
///
/// `settings.schemaVersion` houdt bij welke versie de opgeslagen instellingen
/// hebben. Bij elke app-start draait `migrateIfNeeded` de migraties die nog
/// niet gedraaid hebben, in volgorde. Een migratie zet oude sleutels/waardes
/// om (`renameKey`) in plaats van ze weg te gooien, en vult nooit een
/// standaardwaarde in over een waarde die de gebruiker al heeft.
///
/// Een nieuwe instelling met een standaardwaarde heeft geen migratie nodig:
/// de getters lezen `defaults.object(forKey:) ?? standaard`. Voeg alleen een
/// migratie toe als een sleutel hernoemd wordt of een waarde van vorm verandert.
public enum SettingsMigrator {

    public enum Keys {
        /// `Int`: versie van de opgeslagen instellingen (0 = van vóór het versiebeheer).
        public static let schemaVersion = "settings.schemaVersion"
    }

    public struct Migration {
        /// De versie waar deze migratie naartoe brengt.
        public let version: Int
        public let migrate: (UserDefaults) -> Void

        public init(version: Int, migrate: @escaping (UserDefaults) -> Void) {
            self.version = version
            self.migrate = migrate
        }
    }

    /// Alle migraties, oplopend op versie.
    ///
    /// - 1: begin van het versiebeheer. Er zijn geen hernoemde sleutels; de
    ///   bestaande instellingen blijven ongewijzigd en krijgen versie 1.
    public static let migrations: [Migration] = [
        Migration(version: 1) { _ in }
    ]

    public static var currentVersion: Int { migrations.map(\.version).max() ?? 0 }

    /// Draait alle migraties met een hogere versie dan de opgeslagen versie.
    /// Een nieuwere opgeslagen versie (downgrade) wordt niet aangeraakt.
    /// - Returns: de versies die gedraaid hebben.
    @discardableResult
    public static func migrateIfNeeded(defaults: UserDefaults = .standard, migrations: [Migration] = SettingsMigrator.migrations) -> [Int] {
        let stored = defaults.integer(forKey: Keys.schemaVersion)
        var ran: [Int] = []
        for migration in migrations.sorted(by: { $0.version < $1.version }) where migration.version > stored {
            migration.migrate(defaults)
            defaults.set(migration.version, forKey: Keys.schemaVersion)
            ran.append(migration.version)
        }
        return ran
    }

    /// Verplaatst de waarde van `oldKey` naar `newKey`, tenzij `newKey` al een
    /// waarde heeft (die van de gebruiker wint). De oude sleutel wordt pas na
    /// het kopiëren verwijderd.
    public static func renameKey(_ oldKey: String, to newKey: String, in defaults: UserDefaults) {
        guard let value = defaults.object(forKey: oldKey) else { return }
        if defaults.object(forKey: newKey) == nil {
            defaults.set(value, forKey: newKey)
        }
        defaults.removeObject(forKey: oldKey)
    }

    // MARK: - Instellingen in de backup

    /// Instellingen die in een backup meegaan. Toestelgebonden waardes (de
    /// bookmark van de backupmap, tijdstempels, foutmeldingen) horen er niet bij.
    public static let backedUpKeys: [String] = [
        Keys.schemaVersion,
        ThemeStore.Keys.selectedPaletteID,
        ThemeStore.Keys.customThemes,
        MedalStore.Keys.unlocked,
        MedalStore.Keys.initialSyncDone,
        RewardSettings.Keys.animationsEnabled,
        RewardSettings.Keys.medalNotificationsEnabled,
        RewardSettings.Keys.openReportsAfterSave,
        ReminderSettings.Keys.isEnabled,
        ReminderSettings.Keys.hour,
        ReminderSettings.Keys.minute,
        ReminderSettings.Keys.weekdaysOnly,
        ReminderSettings.Keys.message,
        CalendarViewModel.includeBacktestKey,
        DashboardFilterSettings.key,
        CSVMappingStore.key,
        OnboardingSettings.Keys.hasSeenOnboarding,
        BackupSettings.Keys.autoBackupFrequency,
        BackupSettings.Keys.autoBackupKeepCount,
        AppLockService.Keys.isEnabled,
        AppLockService.Keys.gracePeriod,
        SeedService.Keys.seededInstrumentSymbols,
        LiveQuoteSettings.Keys.isEnabled,
        LiveQuoteSettings.Keys.symbolOverride
    ]

    /// De huidige waardes van `backedUpKeys` (alleen de sleutels die gezet zijn).
    public static func snapshot(from defaults: UserDefaults = .standard) -> [String: SettingValue] {
        var result: [String: SettingValue] = [:]
        for key in backedUpKeys {
            if let value = SettingValue(defaultsObject: defaults.object(forKey: key)) {
                result[key] = value
            }
        }
        return result
    }

    /// Zet instellingen uit een backup terug. Onbekende sleutels (uit een
    /// andere app-versie) worden genegeerd; daarna draaien de migraties, zodat
    /// een backup van een oudere versie ook omgezet wordt.
    public static func restore(_ settings: [String: SettingValue], into defaults: UserDefaults = .standard) {
        let allowed = Set(backedUpKeys)
        for (key, value) in settings where allowed.contains(key) {
            defaults.set(value.defaultsObject, forKey: key)
        }
        if settings[Keys.schemaVersion] == nil {
            defaults.removeObject(forKey: Keys.schemaVersion)
        }
        migrateIfNeeded(defaults: defaults)
    }
}
