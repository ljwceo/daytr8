import Foundation

/// Onboarding-status, opgeslagen in `UserDefaults` (net als `BackupSettings`).
///
/// `defaults` is injecteerbaar zodat tests een eigen suite kunnen gebruiken.
final class OnboardingSettings {

    enum Keys {
        /// `Bool`: de welkomstmelding is al eens getoond.
        static let hasSeenOnboarding = "onboarding.hasSeenOnboarding"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasSeenOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasSeenOnboarding) }
    }

    /// Alleen bij de allereerste start van de app.
    var shouldShowWelcomeBanner: Bool { !hasSeenOnboarding }

    /// Zet de vlag terug, zodat de welkomstmelding bij de volgende start weer verschijnt.
    func reset() {
        defaults.removeObject(forKey: Keys.hasSeenOnboarding)
    }
}
