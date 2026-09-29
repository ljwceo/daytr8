import Foundation

/// Maakt van een `CustomTheme` een volledig `ThemePalette`, controleert het
/// contrast (WCAG AA) en genereert paletten vanuit één accentkleur.
/// Puur rekenwerk, zodat het zonder UI te testen is.
enum ThemePaletteGenerator {

    /// Minimaal contrast voor tekst, accent en winst/verlies (WCAG AA, normale tekst).
    static let minimumTextContrast = 4.5
    /// Minimaal contrast voor hulptekst, iconen en waarschuwingen (grote tekst / UI).
    static let minimumLargeContrast = 3.0

    /// Een gekozen kleur met te weinig contrast op een van de oppervlakken.
    struct ContrastIssue: Identifiable, Equatable, Sendable {
        let field: CustomTheme.Field
        /// Laagste gemeten contrast (op achtergrond, kaart of verhoogd oppervlak).
        let ratio: Double
        let minimum: Double

        var id: CustomTheme.Field { field }
    }

    /// Velden die als tekst/voorgrond op de oppervlakken staan.
    static let foregroundFields: [CustomTheme.Field] = [.text, .accent, .profit, .loss]

    // MARK: - Palet

    static func palette(for theme: CustomTheme) -> ThemePalette {
        let background = theme[.background]
        let card = theme[.card]
        let text = theme[.text]
        let accent = theme[.accent]
        let isDark = background.relativeLuminance < 0.2

        let elevated = elevatedSurface(card: card, text: text, isDark: isDark)
        let surfaces = [background, card, elevated]

        return ThemePalette(
            id: theme.id,
            name: theme.name,
            group: .custom,
            isDark: isDark,
            background: background,
            card: card,
            elevated: elevated,
            textPrimary: text,
            textSecondary: text.mixed(with: card, amount: 0.3).ensuringContrast(on: surfaces, minimum: minimumTextContrast),
            textTertiary: text.mixed(with: card, amount: 0.45).ensuringContrast(on: surfaces, minimum: minimumLargeContrast),
            accent: accent,
            onAccent: accent.readableForeground,
            profit: theme[.profit],
            loss: theme[.loss],
            neutral: text.mixed(with: background, amount: 0.4).ensuringContrast(on: surfaces, minimum: minimumLargeContrast),
            warning: (isDark ? HexColor("#FFBF3C") : HexColor("#8A5A00")).ensuringContrast(on: surfaces, minimum: minimumLargeContrast)
        )
    }

    /// Chips/modals: de kaartkleur een klein stukje richting de tekstkleur.
    static func elevatedSurface(card: HexColor, text: HexColor, isDark: Bool) -> HexColor {
        card.mixed(with: text, amount: isDark ? 0.07 : 0.06)
    }

    // MARK: - Contrast

    /// Alle voorgrondkleuren die niet genoeg contrast hebben.
    static func contrastIssues(for theme: CustomTheme) -> [ContrastIssue] {
        let surfaces = surfaces(of: theme)
        return foregroundFields.compactMap { field in
            let ratio = theme[field].minimumContrast(on: surfaces)
            guard ratio < minimumTextContrast else { return nil }
            return ContrastIssue(field: field, ratio: ratio, minimum: minimumTextContrast)
        }
    }

    /// Het thema met alle voorgrondkleuren zo weinig mogelijk aangepast tot
    /// ze WCAG AA halen. Achtergrond en kaart blijven ongewijzigd.
    static func autoCorrected(_ theme: CustomTheme) -> CustomTheme {
        var corrected = theme
        // Twee rondes: het verhoogde oppervlak hangt af van de tekstkleur,
        // dus na het corrigeren van de tekst opnieuw controleren.
        for _ in 0..<2 {
            let surfaces = surfaces(of: corrected)
            for field in foregroundFields {
                corrected[field] = corrected[field].ensuringContrast(on: surfaces, minimum: minimumTextContrast)
            }
        }
        return corrected
    }

    static func surfaces(of theme: CustomTheme) -> [HexColor] {
        let background = theme[.background]
        let isDark = background.relativeLuminance < 0.2
        return [background, theme[.card], elevatedSurface(card: theme[.card], text: theme[.text], isDark: isDark)]
    }

    // MARK: - Genereren

    /// Een passend palet rond één accentkleur: achtergrond en kaart in een
    /// gedempte tint van het accent, tekst bijna wit/zwart, en winst/verlies
    /// in groen/rood. Daarna automatisch op contrast gecorrigeerd.
    static func generated(fromAccent accent: HexColor, dark: Bool, id: String, name: String) -> CustomTheme {
        let base = HSBColor(accent)
        let hue = base.hue
        let tint = base.saturation

        let background: HSBColor
        let card: HSBColor
        let text: HSBColor
        let profit: HSBColor
        let loss: HSBColor
        if dark {
            background = HSBColor(hue: hue, saturation: min(tint * 0.5, 0.45), brightness: 0.10)
            card = HSBColor(hue: hue, saturation: min(tint * 0.45, 0.40), brightness: 0.16)
            text = HSBColor(hue: hue, saturation: min(tint * 0.06, 0.05), brightness: 0.96)
            profit = HSBColor(hue: 0.40, saturation: 0.70, brightness: 0.85)
            loss = HSBColor(hue: 0.99, saturation: 0.58, brightness: 1.0)
        } else {
            background = HSBColor(hue: hue, saturation: min(tint * 0.12, 0.10), brightness: 0.97)
            card = HSBColor(hue: hue, saturation: min(tint * 0.03, 0.03), brightness: 1.0)
            text = HSBColor(hue: hue, saturation: min(tint * 0.4, 0.35), brightness: 0.12)
            profit = HSBColor(hue: 0.40, saturation: 0.90, brightness: 0.42)
            loss = HSBColor(hue: 0.99, saturation: 0.82, brightness: 0.72)
        }

        let theme = CustomTheme(
            id: id, name: name,
            accent: accent.hex,
            background: background.hexColor.hex,
            card: card.hexColor.hex,
            text: text.hexColor.hex,
            profit: profit.hexColor.hex,
            loss: loss.hexColor.hex
        )
        return autoCorrected(theme)
    }
}
