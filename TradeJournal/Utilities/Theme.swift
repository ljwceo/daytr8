import SwiftUI

/// Centrale kleuren en styling voor de TradeJournal-app.
/// Alle views gebruiken deze constants zodat een themawijziging op één plek gebeurt.
enum Theme {

    // MARK: - Basiskleuren

    /// Achtergrond van het hoofdscherm (donker, bijna zwart).
    static let background = Color(red: 0.05, green: 0.06, blue: 0.08)

    /// Achtergrond van kaarten en secties, iets lichter dan `background`.
    static let card = Color(red: 0.10, green: 0.11, blue: 0.14)

    /// Extra hoge oppervlakken (modals, popovers).
    static let elevated = Color(red: 0.14, green: 0.15, blue: 0.18)

    /// Subtiele scheidingslijnen.
    static let separator = Color.white.opacity(0.08)

    // MARK: - Semantische kleuren

    /// Winst / positief resultaat.
    static let profit = Color(red: 0.15, green: 0.78, blue: 0.45)

    /// Verlies / negatief resultaat.
    static let loss = Color(red: 0.94, green: 0.31, blue: 0.36)

    /// Neutraal / breakeven.
    static let neutral = Color(red: 0.60, green: 0.62, blue: 0.68)

    /// Accentkleur voor knoppen, actieve tab, links.
    static let accent = Color(red: 0.30, green: 0.68, blue: 1.00)

    /// Waarschuwing (bijv. dicht bij daily loss limit).
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.20)

    // MARK: - Tekstkleuren

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.48)

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
}
