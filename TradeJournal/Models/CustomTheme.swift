import Foundation

/// Een door de gebruiker gemaakt kleurthema (Meer → Thema → Eigen thema's).
///
/// Bewaart alleen de zes kleuren die de gebruiker kiest; de overige tokens
/// (verhoogd oppervlak, secundaire tekst, `onAccent`, …) leidt
/// `ThemePaletteGenerator` er zo af dat ze leesbaar blijven. Wordt als JSON
/// in `UserDefaults` bewaard (`ThemeStore.Keys.customThemes`) en gaat mee in
/// de backup.
struct CustomTheme: Codable, Identifiable, Equatable, Hashable, Sendable {

    /// De kleuren die de gebruiker zelf instelt.
    enum Field: String, Codable, CaseIterable, Identifiable, Sendable {
        case accent
        case background
        case card
        case text
        case profit
        case loss

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .accent: return "Accent"
            case .background: return "Achtergrond"
            case .card: return "Kaart"
            case .text: return "Tekst"
            case .profit: return "Winst"
            case .loss: return "Verlies"
            }
        }
    }

    /// Prefix van de id's, zodat ze nooit botsen met de ingebouwde paletten.
    static let idPrefix = "custom-"

    var id: String
    var name: String
    var accent: String
    var background: String
    var card: String
    var text: String
    var profit: String
    var loss: String

    init(id: String = CustomTheme.idPrefix + UUID().uuidString, name: String,
         accent: String, background: String, card: String, text: String, profit: String, loss: String) {
        self.id = id
        self.name = name
        self.accent = accent
        self.background = background
        self.card = card
        self.text = text
        self.profit = profit
        self.loss = loss
    }

    /// Nieuw eigen thema met de kleuren van een bestaand palet als startpunt.
    init(id: String = CustomTheme.idPrefix + UUID().uuidString, name: String, basedOn palette: ThemePalette) {
        self.init(
            id: id, name: name,
            accent: palette.accent.hex, background: palette.background.hex, card: palette.card.hex,
            text: palette.textPrimary.hex, profit: palette.profit.hex, loss: palette.loss.hex
        )
    }

    subscript(field: Field) -> HexColor {
        get {
            switch field {
            case .accent: return HexColor(accent)
            case .background: return HexColor(background)
            case .card: return HexColor(card)
            case .text: return HexColor(text)
            case .profit: return HexColor(profit)
            case .loss: return HexColor(loss)
            }
        }
        set {
            switch field {
            case .accent: accent = newValue.hex
            case .background: background = newValue.hex
            case .card: card = newValue.hex
            case .text: text = newValue.hex
            case .profit: profit = newValue.hex
            case .loss: loss = newValue.hex
            }
        }
    }

    /// Het volledige palet waar `Theme` uit leest.
    var palette: ThemePalette { ThemePaletteGenerator.palette(for: self) }
}
