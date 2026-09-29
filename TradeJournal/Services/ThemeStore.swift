import Foundation
import Observation

/// Houdt het gekozen kleurthema bij en bewaart de keuze in `UserDefaults`
/// (net als `BackupSettings`), zodat hij een herstart overleeft.
///
/// `Theme` leest zijn kleuren uit `ThemeStore.shared.palette`. Omdat de store
/// `@Observable` is, registreert elke view die tijdens `body` een `Theme`-kleur
/// leest zich automatisch op het palet: wisselen van thema hertekent de app
/// live, zonder dat bestaande views aangepast hoeven te worden.
///
/// Naast de ingebouwde paletten beheert de store de eigen thema's van de
/// gebruiker (`CustomTheme`), als JSON in `UserDefaults`.
///
/// `defaults` is injecteerbaar zodat tests een eigen suite kunnen gebruiken.
@Observable
final class ThemeStore {

    enum Keys {
        /// `String`: `ThemePalette.id` van het gekozen thema.
        static let selectedPaletteID = "theme.selectedPaletteID"
        /// `String` (JSON): de eigen thema's (`[CustomTheme]`).
        static let customThemes = "theme.customThemes"
    }

    /// De app-brede store waar `Theme` uit leest.
    static let shared = ThemeStore()

    private(set) var palette: ThemePalette

    /// Eigen thema's, in de volgorde waarin ze gemaakt zijn.
    private(set) var customThemes: [CustomTheme]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let customThemes = Self.loadCustomThemes(from: defaults)
        self.customThemes = customThemes
        self.palette = Self.palette(withID: defaults.string(forKey: Keys.selectedPaletteID), customThemes: customThemes) ?? .standard
    }

    /// Eigen thema's als paletten (voor de themakiezer).
    var customPalettes: [ThemePalette] { customThemes.map(\.palette) }

    /// Het eigen thema dat nu actief is, of `nil` bij een ingebouwd palet.
    var selectedCustomTheme: CustomTheme? {
        customThemes.first { $0.id == palette.id }
    }

    /// Leest de keuze opnieuw uit `UserDefaults` (na het terugzetten van een backup).
    func reload() {
        let themes = Self.loadCustomThemes(from: defaults)
        if themes != customThemes { customThemes = themes }
        let stored = Self.palette(withID: defaults.string(forKey: Keys.selectedPaletteID), customThemes: themes) ?? .standard
        if stored != palette { palette = stored }
    }

    /// Kiest en bewaart een thema.
    func select(_ palette: ThemePalette) {
        guard palette != self.palette else { return }
        self.palette = palette
        defaults.set(palette.id, forKey: Keys.selectedPaletteID)
    }

    /// Terug naar het standaardthema (*Donker*). Eigen thema's blijven bewaard.
    func resetToStandard() {
        select(.standard)
    }

    // MARK: - Eigen thema's

    /// Voegt een eigen thema toe of werkt het bij. Is het thema actief (of
    /// `select` is `true`), dan ziet de app de nieuwe kleuren meteen.
    func save(_ theme: CustomTheme, select shouldSelect: Bool = true) {
        var themes = customThemes
        if let index = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[index] = theme
        } else {
            themes.append(theme)
        }
        customThemes = themes
        persistCustomThemes()

        if shouldSelect || palette.id == theme.id {
            select(theme.palette)
        }
    }

    /// Verwijdert een eigen thema; was het actief, dan wordt het standaardthema gekozen.
    func deleteCustomTheme(id: String) {
        customThemes.removeAll { $0.id == id }
        persistCustomThemes()
        if palette.id == id {
            select(.standard)
        }
    }

    // MARK: - Opslag

    private func persistCustomThemes() {
        guard let data = try? JSONEncoder().encode(customThemes),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Keys.customThemes)
    }

    private static func loadCustomThemes(from defaults: UserDefaults) -> [CustomTheme] {
        guard let json = defaults.string(forKey: Keys.customThemes),
              let data = json.data(using: .utf8),
              let themes = try? JSONDecoder().decode([CustomTheme].self, from: data) else { return [] }
        return themes
    }

    private static func palette(withID id: String?, customThemes: [CustomTheme]) -> ThemePalette? {
        if let builtIn = ThemePalette.palette(withID: id) { return builtIn }
        guard let id else { return nil }
        return customThemes.first { $0.id == id }?.palette
    }
}
