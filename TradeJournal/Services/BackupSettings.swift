import Foundation

/// Hoe vaak de automatische backup naar de gekozen map draait.
public enum AutoBackupFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case everyLaunch = "every_launch"
    case daily

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Uit"
        case .everyLaunch: return "Bij elke app-start"
        case .daily: return "Dagelijks"
        }
    }
}

/// Backup-instellingen en -status, opgeslagen in `UserDefaults` (dus buiten
/// SwiftData — zo overleven ze een restore en blijven ze los van het journal).
///
/// `defaults` is injecteerbaar zodat tests een eigen suite kunnen gebruiken.
public final class BackupSettings {

    public enum Keys {
        /// `Double` (timeIntervalSince1970); 0 = nog nooit. Ook gelezen via
        /// `@AppStorage` door `BackupReminderBannerView`.
        public static let lastBackupDate = "backup.lastBackupDate"
        public static let lastAutoBackupDate = "backup.lastAutoBackupDate"
        public static let autoBackupFrequency = "backup.autoBackupFrequency"
        public static let autoBackupFolderBookmark = "backup.autoBackupFolderBookmark"
        public static let autoBackupFolderName = "backup.autoBackupFolderName"
        public static let autoBackupKeepCount = "backup.autoBackupKeepCount"
        /// `Bool`: de gebruiker heeft de backupherinnering bewust uitgezet.
        /// Ook gelezen via `@AppStorage` door `BackupReminderBannerView`.
        public static let reminderDismissed = "backup.reminderDismissed"
        /// `String`: foutmelding van de laatste mislukte automatische backup;
        /// leeg = laatste poging gelukt. Ook gelezen via `@AppStorage`.
        public static let lastAutoBackupError = "backup.lastAutoBackupError"
    }

    /// Na zoveel tijd zonder backup toont de app een waarschuwing (SPEC §9).
    public static let staleInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Minimale tijd tussen twee dagelijkse automatische backups.
    public static let dailyInterval: TimeInterval = 24 * 60 * 60

    public static let defaultKeepCount = 10

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Status

    public var lastBackupDate: Date? {
        get { Self.date(from: defaults.double(forKey: Keys.lastBackupDate)) }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Keys.lastBackupDate) }
    }

    public var lastAutoBackupDate: Date? {
        get { Self.date(from: defaults.double(forKey: Keys.lastAutoBackupDate)) }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Keys.lastAutoBackupDate) }
    }

    /// Foutmelding van de laatste mislukte automatische backup (`nil` = geen).
    public var lastAutoBackupError: String? {
        get { defaults.string(forKey: Keys.lastAutoBackupError).flatMap { $0.isEmpty ? nil : $0 } }
        set { defaults.set(newValue ?? "", forKey: Keys.lastAutoBackupError) }
    }

    /// Registreert een geslaagde backup (handmatig of automatisch).
    public func recordBackup(at date: Date = Date(), automatic: Bool = false) {
        lastBackupDate = date
        if automatic { lastAutoBackupDate = date }
    }

    /// De gebruiker heeft de herinnering weggeklikt (en bevestigd dat hij
    /// begrijpt dat backups belangrijk zijn). Terug aan te zetten in Backup & herstel.
    public var isReminderDismissed: Bool {
        get { defaults.bool(forKey: Keys.reminderDismissed) }
        set { defaults.set(newValue, forKey: Keys.reminderDismissed) }
    }

    // MARK: - Automatische backup

    public var autoBackupFrequency: AutoBackupFrequency {
        get { defaults.string(forKey: Keys.autoBackupFrequency).flatMap(AutoBackupFrequency.init(rawValue:)) ?? .off }
        set { defaults.set(newValue.rawValue, forKey: Keys.autoBackupFrequency) }
    }

    /// Bookmark-data van de door de gebruiker gekozen map in Bestanden.
    public var autoBackupFolderBookmark: Data? {
        get { defaults.data(forKey: Keys.autoBackupFolderBookmark) }
        set { defaults.set(newValue, forKey: Keys.autoBackupFolderBookmark) }
    }

    /// Weergavenaam van de gekozen map.
    public var autoBackupFolderName: String? {
        get { defaults.string(forKey: Keys.autoBackupFolderName) }
        set { defaults.set(newValue, forKey: Keys.autoBackupFolderName) }
    }

    /// Hoeveel automatische backups er in de map bewaard blijven.
    public var autoBackupKeepCount: Int {
        get {
            let stored = defaults.integer(forKey: Keys.autoBackupKeepCount)
            return stored > 0 ? stored : Self.defaultKeepCount
        }
        set { defaults.set(max(1, newValue), forKey: Keys.autoBackupKeepCount) }
    }

    // MARK: - Pure beslisregels

    /// `true` als er nog nooit een backup is gemaakt of de laatste ouder is
    /// dan 7 dagen.
    public static func isStale(lastBackup: Date?, now: Date = Date()) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) > staleInterval
    }

    /// Of de backupherinnering (dashboardbanner, icoon in Meer) getoond wordt.
    public static func shouldShowReminder(lastBackup: Date?, dismissed: Bool, now: Date = Date()) -> Bool {
        !dismissed && isStale(lastBackup: lastBackup, now: now)
    }

    public func isBackupStale(now: Date = Date()) -> Bool {
        Self.isStale(lastBackup: lastBackupDate, now: now)
    }

    /// Of er bij dit moment (`isLaunch`: app-start i.p.v. terugkeer naar de
    /// voorgrond) een automatische backup moet draaien.
    public static func isAutoBackupDue(
        frequency: AutoBackupFrequency,
        hasFolder: Bool,
        lastAutoBackup: Date?,
        isLaunch: Bool,
        now: Date = Date()
    ) -> Bool {
        guard hasFolder else { return false }
        switch frequency {
        case .off:
            return false
        case .everyLaunch:
            return isLaunch
        case .daily:
            guard let lastAutoBackup else { return true }
            return now.timeIntervalSince(lastAutoBackup) >= dailyInterval
        }
    }

    public func isAutoBackupDue(isLaunch: Bool, now: Date = Date()) -> Bool {
        Self.isAutoBackupDue(
            frequency: autoBackupFrequency,
            hasFolder: autoBackupFolderBookmark != nil,
            lastAutoBackup: lastAutoBackupDate,
            isLaunch: isLaunch,
            now: now
        )
    }

    private static func date(from interval: Double) -> Date? {
        interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }
}
