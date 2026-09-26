import SwiftUI

/// Centrale kleuren en styling voor de TradeJournal-app.
/// Alle views gebruiken deze tokens zodat een themawijziging op één plek gebeurt.
///
/// De kleuren komen uit het actieve `ThemePalette` (`ThemeStore.shared`).
/// Omdat de store `@Observable` is, tekenen views die deze kleuren in `body`
/// lezen vanzelf opnieuw zodra de gebruiker een ander thema kiest.
enum Theme {

    private static var palette: ThemePalette { ThemeStore.shared.palette }

    // MARK: - Basiskleuren

    /// Achtergrond van het hoofdscherm.
    static var background: Color { palette.background.color }

    /// Achtergrond van kaarten en secties (oppervlak), iets af van `background`.
    static var card: Color { palette.card.color }

    /// Extra hoge oppervlakken (modals, popovers, chips).
    static var elevated: Color { palette.elevated.color }

    /// Subtiele scheidingslijnen en randen.
    static var separator: Color { palette.textPrimary.color.opacity(palette.borderOpacity) }

    /// Rand rond kaarten/stalen; zelfde token als `separator`.
    static var border: Color { separator }

    // MARK: - Semantische kleuren

    /// Winst / positief resultaat.
    static var profit: Color { palette.profit.color }

    /// Verlies / negatief resultaat.
    static var loss: Color { palette.loss.color }

    /// Neutraal / breakeven.
    static var neutral: Color { palette.neutral.color }

    /// Accentkleur voor knoppen, actieve tab, links.
    static var accent: Color { palette.accent.color }

    /// Tekst en iconen op een accentvlak (bijv. primaire knop).
    static var onAccent: Color { palette.onAccent.color }

    /// Waarschuwing (bijv. dicht bij daily loss limit).
    static var warning: Color { palette.warning.color }

    // MARK: - Tekstkleuren

    static var textPrimary: Color { palette.textPrimary.color }
    static var textSecondary: Color { palette.textSecondary.color }
    static var textTertiary: Color { palette.textTertiary.color }

    /// Schaduw onder zwevende elementen (bijv. de welkomstmelding).
    static var shadow: Color { Color.black.opacity(palette.isDark ? 0.45 : 0.15) }

    /// Color scheme dat bij het actieve thema hoort (voor system-controls).
    static var colorScheme: ColorScheme { palette.colorScheme }

    // MARK: - Metrics

    /// Standaard hoekradius voor kaarten.
    static let cornerRadius: CGFloat = 16

    /// Kleinere hoekradius voor chips, badges, kleine knoppen.
    static let smallCornerRadius: CGFloat = 10

    /// Standaard binnenmarge voor kaarten.
    static let cardPadding: CGFloat = 16

    /// Geeft groen bij winst, rood bij verlies, grijs bij nul.
    static func color(forPnL value: Double) -> Color {
        if value > 0 { return profit }
        if value < 0 { return loss }
        return neutral
    }

    /// Compacte $-notatie voor kalendercellen en kleine kaarten
    /// (bijv. "$1.2k", "-$340") waar een volledig currency-format niet past.
    static func compactCurrency(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        if magnitude >= 1000 {
            return "\(sign)$\(String(format: "%.1fk", magnitude / 1000))"
        }
        return "\(sign)$\(String(format: "%.0f", magnitude))"
    }
}

extension Color {
    /// Parseert een hex-kleurcode ("#RRGGBB" of "RRGGBB"), zoals opgeslagen op
    /// `Confluence`/`Tag`/`Mistake`/`Playbook`, naar een `Color`. Valt terug
    /// op `Theme.neutral` bij een ongeldige string.
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else {
            self = Theme.neutral
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
