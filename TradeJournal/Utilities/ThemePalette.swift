import SwiftUI

/// Een kleur als hex-waarde ("#RRGGBB"). Puur data, zodat paletten zonder UI
/// te testen zijn (contrastberekening volgens WCAG 2.1).
struct HexColor: Equatable, Hashable, Sendable {

    let hex: String
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        let value = UInt64(sanitized, radix: 16) ?? 0
        self.hex = "#" + sanitized.uppercased()
        self.red = Double((value >> 16) & 0xFF) / 255
        self.green = Double((value >> 8) & 0xFF) / 255
        self.blue = Double(value & 0xFF) / 255
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    /// Relatieve luminantie volgens WCAG 2.1.
    var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// Contrastverhouding (1…21) tussen twee kleuren. WCAG AA vraagt ≥ 4,5
    /// voor normale tekst en ≥ 3 voor grote tekst en iconen.
    static func contrastRatio(_ a: HexColor, _ b: HexColor) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/// Eén kleurthema: de centrale tokens waar `Theme` uit leest.
///
/// Winst/verlies-kleuren zijn per palet gekozen zodat ze op achtergrond,
/// kaart en verhoogd oppervlak minimaal WCAG AA (4,5:1) halen — dat wordt
/// afgedwongen door `ThemeStoreTests`.
struct ThemePalette: Identifiable, Equatable, Hashable, Sendable {

    enum Group: String, CaseIterable, Identifiable, Sendable {
        case pastel
        case solid

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .solid: return AppStrings.Themes.groupSolid
            case .pastel: return AppStrings.Themes.groupPastel
            }
        }
    }

    let id: String
    let name: String
    let group: Group
    /// Donker palet → system-controls in dark mode, anders light mode.
    let isDark: Bool

    /// Achtergrond van schermen.
    let background: HexColor
    /// Oppervlak van kaarten en secties.
    let card: HexColor
    /// Hoger oppervlak (chips, modals, popovers).
    let elevated: HexColor
    let textPrimary: HexColor
    let textSecondary: HexColor
    let textTertiary: HexColor
    let accent: HexColor
    /// Tekst/iconen óp een accentvlak (bijv. primaire knop).
    let onAccent: HexColor
    let profit: HexColor
    let loss: HexColor
    let neutral: HexColor
    let warning: HexColor

    /// Rand- en scheidingslijnkleur: tekstkleur op lage dekking.
    var borderOpacity: Double { isDark ? 0.10 : 0.12 }

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    /// Oppervlakken waarop tekst voorkomt (voor contrastcontrole).
    var surfaces: [HexColor] { [background, card, elevated] }
}

// MARK: - Standaardpaletten

extension ThemePalette {

    /// Standaardthema bij eerste start.
    static let standard = donker

    static let all: [ThemePalette] = [
        donker, licht, middernachtblauw, bosgroen,
        lavendel, mint, perzik, babyblauw
    ]

    static func palette(withID id: String?) -> ThemePalette? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static func palettes(in group: Group) -> [ThemePalette] {
        all.filter { $0.group == group }
    }

    // MARK: Effen

    static let donker = ThemePalette(
        id: "donker", name: AppStrings.Themes.donker, group: .solid, isDark: true,
        background: HexColor("#17191D"), card: HexColor("#22252B"), elevated: HexColor("#2C3037"),
        textPrimary: HexColor("#F2F3F5"), textSecondary: HexColor("#B4B8C0"), textTertiary: HexColor("#8E939C"),
        accent: HexColor("#5AB0FF"), onAccent: HexColor("#0B1220"),
        profit: HexColor("#34D17F"), loss: HexColor("#FF6B70"), neutral: HexColor("#9CA1AA"), warning: HexColor("#FFBF3C")
    )

    static let licht = ThemePalette(
        id: "licht", name: AppStrings.Themes.licht, group: .solid, isDark: false,
        background: HexColor("#F2F3F5"), card: HexColor("#FFFFFF"), elevated: HexColor("#E6E8EC"),
        textPrimary: HexColor("#14161A"), textSecondary: HexColor("#474D57"), textTertiary: HexColor("#686E79"),
        accent: HexColor("#0A58BA"), onAccent: HexColor("#FFFFFF"),
        profit: HexColor("#097038"), loss: HexColor("#C0232C"), neutral: HexColor("#5F6670"), warning: HexColor("#8A5A00")
    )

    static let middernachtblauw = ThemePalette(
        id: "middernachtblauw", name: AppStrings.Themes.middernachtblauw, group: .solid, isDark: true,
        background: HexColor("#0B1530"), card: HexColor("#15224A"), elevated: HexColor("#1D2C5A"),
        textPrimary: HexColor("#EEF2FF"), textSecondary: HexColor("#B3BEDD"), textTertiary: HexColor("#8C9AC2"),
        accent: HexColor("#7FB2FF"), onAccent: HexColor("#0B1530"),
        profit: HexColor("#3EDC8F"), loss: HexColor("#FF7A85"), neutral: HexColor("#A3ADC8"), warning: HexColor("#FFC64D")
    )

    static let bosgroen = ThemePalette(
        id: "bosgroen", name: AppStrings.Themes.bosgroen, group: .solid, isDark: true,
        background: HexColor("#0F1F18"), card: HexColor("#173026"), elevated: HexColor("#1F3B2F"),
        textPrimary: HexColor("#EEF6F0"), textSecondary: HexColor("#B2C9BA"), textTertiary: HexColor("#8BA896"),
        accent: HexColor("#8FD6E8"), onAccent: HexColor("#0F1F18"),
        profit: HexColor("#5BE39A"), loss: HexColor("#FF8080"), neutral: HexColor("#A4B5AA"), warning: HexColor("#FFC857")
    )

    // MARK: Pastel

    static let lavendel = ThemePalette(
        id: "lavendel", name: AppStrings.Themes.lavendel, group: .pastel, isDark: false,
        background: HexColor("#F1ECFA"), card: HexColor("#FBF9FE"), elevated: HexColor("#E6DDF5"),
        textPrimary: HexColor("#1F1A2E"), textSecondary: HexColor("#4B4460"), textTertiary: HexColor("#6A6182"),
        accent: HexColor("#5A3DB3"), onAccent: HexColor("#FFFFFF"),
        profit: HexColor("#0A7239"), loss: HexColor("#B3212A"), neutral: HexColor("#5E5870"), warning: HexColor("#855400")
    )

    static let mint = ThemePalette(
        id: "mint", name: AppStrings.Themes.mint, group: .pastel, isDark: false,
        background: HexColor("#E6F5EE"), card: HexColor("#F7FCFA"), elevated: HexColor("#D3EDE1"),
        textPrimary: HexColor("#12241C"), textSecondary: HexColor("#3B564A"), textTertiary: HexColor("#587267"),
        accent: HexColor("#1B5C9C"), onAccent: HexColor("#FFFFFF"),
        profit: HexColor("#096A34"), loss: HexColor("#B0222E"), neutral: HexColor("#56655E"), warning: HexColor("#7E5100")
    )

    static let perzik = ThemePalette(
        id: "perzik", name: AppStrings.Themes.perzik, group: .pastel, isDark: false,
        background: HexColor("#FDEEE4"), card: HexColor("#FFF9F5"), elevated: HexColor("#F7DDCB"),
        textPrimary: HexColor("#2A1A12"), textSecondary: HexColor("#5A4135"), textTertiary: HexColor("#775E51"),
        accent: HexColor("#0E6672"), onAccent: HexColor("#FFFFFF"),
        profit: HexColor("#0A6E3B"), loss: HexColor("#AE1F2A"), neutral: HexColor("#6A5D56"), warning: HexColor("#7E4B00")
    )

    static let babyblauw = ThemePalette(
        id: "babyblauw", name: AppStrings.Themes.babyblauw, group: .pastel, isDark: false,
        background: HexColor("#E6F0FA"), card: HexColor("#F8FBFE"), elevated: HexColor("#D3E4F6"),
        textPrimary: HexColor("#0F1D2E"), textSecondary: HexColor("#3A4E66"), textTertiary: HexColor("#586C84"),
        accent: HexColor("#1A5AAB"), onAccent: HexColor("#FFFFFF"),
        profit: HexColor("#0A6E3B"), loss: HexColor("#B01F2A"), neutral: HexColor("#566273"), warning: HexColor("#7E5100")
    )
}
