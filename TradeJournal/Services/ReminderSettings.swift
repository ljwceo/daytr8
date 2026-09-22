import Foundation

/// Instellingen voor de lokale journal-herinnering, opgeslagen in
/// `UserDefaults` (net als `BackupSettings`). `defaults` is injecteerbaar
/// voor tests.
public final class ReminderSettings {

    public enum Keys {
        public static let isEnabled = "reminder.isEnabled"
        public static let hour = "reminder.hour"
        public static let minute = "reminder.minute"
        public static let weekdaysOnly = "reminder.weekdaysOnly"
        public static let message = "reminder.message"
    }

    public static let defaultHour = 17
    public static let defaultMinute = 30
    public static let defaultMessage = "Vul je journal in: post-market review en regels van vandaag."

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    public var hour: Int {
        get { defaults.object(forKey: Keys.hour) as? Int ?? Self.defaultHour }
        set { defaults.set(min(max(newValue, 0), 23), forKey: Keys.hour) }
    }

    public var minute: Int {
        get { defaults.object(forKey: Keys.minute) as? Int ?? Self.defaultMinute }
        set { defaults.set(min(max(newValue, 0), 59), forKey: Keys.minute) }
    }

    /// Alleen op maandag t/m vrijdag herinneren (standaard aan).
    public var weekdaysOnly: Bool {
        get { defaults.object(forKey: Keys.weekdaysOnly) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.weekdaysOnly) }
    }

    public var message: String {
        get {
            let stored = defaults.string(forKey: Keys.message)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? Self.defaultMessage : stored
        }
        set { defaults.set(newValue, forKey: Keys.message) }
    }
}
