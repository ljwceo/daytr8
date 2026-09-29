import Foundation

/// Instellingen voor animaties en medailles (Meer → Meldingen & rewards),
/// opgeslagen in `UserDefaults` (net als `LiveQuoteSettings`). Views lezen
/// dezelfde sleutels via `@AppStorage`. `defaults` is injecteerbaar voor tests.
public final class RewardSettings {

    public enum Keys {
        /// `Bool`: animatie na het opslaan van een trade (standaard aan).
        public static let animationsEnabled = "rewards.animationsEnabled"
        /// `Bool`: melding bij het behalen van een medaille (standaard aan).
        public static let medalNotificationsEnabled = "rewards.medalNotificationsEnabled"
        /// `Bool`: na het opslaan van een nieuwe trade naar Rapporten (standaard aan).
        public static let openReportsAfterSave = "rewards.openReportsAfterSave"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var animationsEnabled: Bool {
        get { defaults.object(forKey: Keys.animationsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.animationsEnabled) }
    }

    public var medalNotificationsEnabled: Bool {
        get { defaults.object(forKey: Keys.medalNotificationsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.medalNotificationsEnabled) }
    }

    public var openReportsAfterSave: Bool {
        get { defaults.object(forKey: Keys.openReportsAfterSave) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.openReportsAfterSave) }
    }
}
