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
/// `defaults` is injecteerbaar zodat tests een eigen suite kunnen gebruiken.
@Observable
final class ThemeStore {

    enum Keys {
        /// `String`: `ThemePalette.id` van het gekozen thema.
        static let selectedPaletteID = "theme.selectedPaletteID"
    }

    /// De app-brede store waar `Theme` uit leest.
    static let shared = ThemeStore()

    private(set) var palette: ThemePalette

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.palette = ThemePalette.palette(withID: defaults.string(forKey: Keys.selectedPaletteID)) ?? .standard
    }

    /// Kiest en bewaart een thema.
    func select(_ palette: ThemePalette) {
        guard palette != self.palette else { return }
        self.palette = palette
        defaults.set(palette.id, forKey: Keys.selectedPaletteID)
    }
}
