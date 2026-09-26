import Foundation

/// Instellingen voor de live-koerskaart op het dashboard, opgeslagen in
/// `UserDefaults` (net als `ReminderSettings`). `defaults` is injecteerbaar
/// voor tests.
public final class LiveQuoteSettings {

    public enum Keys {
        /// `Bool`: kaart tonen en koersen ophalen (standaard aan).
        public static let isEnabled = "liveQuote.isEnabled"
        /// `String`: vast symbool i.p.v. het laatst getrade instrument (leeg = automatisch).
        public static let symbolOverride = "liveQuote.symbolOverride"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.object(forKey: Keys.isEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    /// `nil` = automatisch (laatst getrade instrument).
    public var symbolOverride: String? {
        get {
            let stored = defaults.string(forKey: Keys.symbolOverride)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? nil : stored
        }
        set { defaults.set(newValue ?? "", forKey: Keys.symbolOverride) }
    }
}
